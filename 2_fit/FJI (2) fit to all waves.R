#these were the dates we used when searching for the range of shift dates
baseline_covid19_waves = data.frame(date = c(as.Date('2021-06-06'),as.Date('2021-10-04'),as.Date('2022-02-01')),
                                                       strain = c('delta','omicron','omicron'))

fit_all_waves <- function(par){
  
  fitting = "on"
  strain_inital = strain_now = 'WT' 
  
  fitting_beta = c(par[1],
                   par[2],
                   par[3])
  
  covid19_waves = baseline_covid19_waves
  covid19_waves$date[1] = covid19_waves$date[1] + round(par[4])
  covid19_waves$date[2] = covid19_waves$date[2] + round(par[5])
  covid19_waves$date[3] = covid19_waves$date[3] + round(par[6])
  
  date_start = as.Date('2021-04-30')
  model_weeks = as.numeric((as.Date('2022-12-31') - date_start)/7)
  
  source(paste(getwd(),"/CommandDeck.R",sep=""),local=TRUE) #15 minutes
  
  # search under reporting
  increments_list = c(100,50,10,5,1,0.25)
  underreporting_tracker = data.frame()
  
  for (repeat_through in 1:length(increments_list)){
    
    increment = increments_list[repeat_through]
    
    if (repeat_through == 1){
      search_list1 = search_list2 = search_list3 = seq(50,1000,by=increments_list[repeat_through])
    } else{
      best_so_far = underreporting_tracker[underreporting_tracker$fit== min(underreporting_tracker$fit, na.rm=TRUE),]
      if (nrow(best_so_far)>1){ #pick best_so_far with min under reporting
        best_so_far = best_so_far %>% mutate(under_reporting_mean = (wave1+wave2+wave3)/3)
        best_so_far = best_so_far[best_so_far$under_reporting_mean == min(best_so_far$under_reporting_mean),]
      }
      best_so_far = unique(best_so_far)
      
      search_list1 = seq(best_so_far$wave1 - increments_list[repeat_through-1],
                         best_so_far$wave1 + increments_list[repeat_through-1],
                         by = increments_list[repeat_through])
      search_list2 = seq(best_so_far$wave2 - increments_list[repeat_through-1],
                         best_so_far$wave2 + increments_list[repeat_through-1],
                         by = increments_list[repeat_through])
      search_list3 = seq(best_so_far$wave3 - increments_list[repeat_through-1],
                         best_so_far$wave3 + increments_list[repeat_through-1],
                         by = increments_list[repeat_through])
    }
    
    for(under_reporting_wave1 in search_list1){
      for (under_reporting_wave2 in search_list2){
        for (under_reporting_wave3 in search_list3){
          
          workshop = case_history %>%
            select(date,rolling_average) %>%
            rename(reported_cases = rolling_average) %>%
            right_join(incidence_log, by = "date") %>%
            left_join(omicron_shift, by = "date") %>%
            rename(omicron = percentage) %>%
            mutate(rolling_average = case_when(
              date >= min(omicron_shift$date[omicron_shift$wave == 2])  & is.na(omicron) == FALSE ~ rolling_average * (1/under_reporting_wave3*omicron + 1/under_reporting_wave2*(1-omicron)),
              date >= min(omicron_shift$date[omicron_shift$wave == 2])  ~ rolling_average * 1/under_reporting_wave3,
              
              date >= min(omicron_shift$date[omicron_shift$wave == 1])  & is.na(omicron) == FALSE ~ rolling_average * (1/under_reporting_wave2*omicron + 1/under_reporting_wave1*(1-omicron)),
              date >= min(omicron_shift$date[omicron_shift$wave == 1])  ~ rolling_average * 1/under_reporting_wave2,
              
              date < min(omicron_shift$date[omicron_shift$wave == 1]) ~ rolling_average * 1/under_reporting_wave1)) %>%
            mutate(fit_statistic = abs(rolling_average - reported_cases)^2) #%>%
            #filter(date<as.Date('2022-10-01'))
          
          fit_statistic = data.frame(
            fit = sum(workshop$fit_statistic,
                      na.rm=TRUE),
            wave1 = under_reporting_wave1,
            wave2 = under_reporting_wave2,
            wave3 = under_reporting_wave3)
          
          underreporting_tracker = rbind(underreporting_tracker,fit_statistic)
        }
      }
    }
  }
  
  fit_statistic = min(underreporting_tracker$fit, na.rm=TRUE)
  
  return(fit_statistic)
}

### Plot under reporting
these_waves = underreporting_tracker[underreporting_tracker$fit == min(underreporting_tracker$fit),]
under_reporting_wave3 = these_waves$wave3
under_reporting_wave2 = these_waves$wave2
under_reporting_wave1 = these_waves$wave1
ggplot() +
  geom_line(data=workshop,aes(x=date,y=rolling_average),na.rm=TRUE) +
  geom_point(data=workshop,aes(x=date,y=reported_cases)) +
  plot_standard 
ggplot() +
  geom_line(data=incidence_log,aes(x=date,y=rolling_average),na.rm=TRUE) +
  plot_standard
#_________________________________________________


### Fit!
require(DEoptim)
full_fit <- DEoptim(fn = fit_all_waves,
                    lower = c(2,4,1.5,
                              -15,0,70
                    ),
                    upper = c(4,6,4.5,
                              0,15,120
                    ),
                    control = list(NP = 30, #ideally 60, possible rerun depending on plot of bestvalit/bestmemit
                                   itermax = 10,
                                   storepopfrom = 1)) 
save(full_fit, file = paste('1_inputs/fit/full_fit',this_setting,Sys.Date(),'.Rdata',sep=''))
#_________________________________________________


### Explore fit
summary(full_fit)
plot(full_fit, plot.type = "bestvalit")
#plot(full_fit, plot.type ="bestmemit")
plot(full_fit, plot.type ="storepop")
to_plot = as.data.frame(full_fit$member$pop)
colnames(to_plot) <- c('beta1','beta2','beta3','seedDate1','seedDate2','seedDate3')
ggplot(to_plot) + geom_histogram(aes(x=beta1),bins=10)
ggplot(to_plot) + geom_histogram(aes(x=beta2),bins=10)
ggplot(to_plot) + geom_histogram(aes(x=beta3),bins=10)
ggplot(to_plot) + geom_point(aes(x=beta1,y=seedDate1))
ggplot(to_plot) + geom_point(aes(x=beta2,y=seedDate2))
ggplot(to_plot) + geom_point(aes(x=beta3,y=seedDate3))
#_________________________________________________


### Save fitted result
par = full_fit$optim$bestmem

#<run inside of f(x)>

incidence_log = incidence_log %>% select(date,daily_cases)

fitted_results = list(
  FR_parameters = parameters,
  FR_next_state = next_state,
  FR_incidence_log_tidy = incidence_log_tidy,
  FR_incidence_log = incidence_log,
  FR_covid19_waves = covid19_waves,
  FR_fitting_beta = fitting_beta
)
save(fitted_results, file = paste("1_inputs/fit/fitted_results_",this_setting,Sys.Date(),".Rdata",sep=""))
#_________________________________________________


### Save fitted result for pregnant women
par = full_fit$optim$bestmem
risk_group_name = 'pregnant_women'; RR_estimate =  2.4

#<run inside of f(x)>

incidence_log = incidence_log %>% select(date,daily_cases)

fitted_results = list(
  FR_parameters = parameters,
  FR_next_state = next_state,
  FR_incidence_log_tidy = incidence_log_tidy,
  FR_incidence_log = incidence_log,
  FR_covid19_waves = covid19_waves,
  FR_fitting_beta = fitting_beta
)
save(fitted_results, file = paste("1_inputs/fit/fitted_results_pregnant_women_",this_setting,Sys.Date(),".Rdata",sep=""))
#_________________________________________________
