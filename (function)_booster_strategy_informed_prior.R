### This function allocates booster doses by age group, risk group and dose
### It has been designed for:
###  antiviral model - allocation of booster doses in sequential years based on previous vaccine rollout


###### Coding vaccine prioritisation strategies
#options(scipen = 100) #removes scientific notation
#options(warn = 0) # = 2 when debugging
#LIMITATION: equal priority between all eligible

###TESTING
# booster_strategy_start_date = as.Date('2023-03-01')
# booster_dose_supply = 9999999999
# booster_rollout_months = 6
# booster_rollout_percentage_pop =  0.163
# 
# booster_delivery_risk_group = c(risk_group_name,'general_public')
# booster_prev_dose_floor = 3
# booster_age_groups = c("18 to 29",  "30 to 44",  "45 to 59", "60 to 69",  "70 to 100")
# 
# booster_prioritised_risk = "Y"
# booster_prioritised_age = c("60 to 69",  "70 to 100")
# 
# booster_strategy_vaccine_type = "Moderna"
# 
# vaccination_history_FINAL_local = vaccination_history_FINAL
#____________



booster_strategy_informed_prior <- function(
    booster_strategy_start_date,       # start of hypothetical vaccination program
    booster_dose_supply,           # num of doses avaliable
    #booster_rollout_months,            # number of months to complete booster program
    booster_rollout_percentage_pop =  0.163, #average across Oceania in 2022 (see `(mech shop) expected daily rollout rate`)
    
    booster_delivery_risk_group = c(risk_group_name,'general_public'),
    booster_prev_dose_floor = max(vaccination_history_FINAL$dose), #down to what dose is willing to be vaccinated?
    booster_prev_dose_ceiling = max(vaccination_history_FINAL$dose), #up to what dose are we targetting?
    booster_age_groups, #what model age groups are willing to be vaccinated?
    
    booster_prioritised_risk,
    booster_prioritised_age = NA, #what age groups are prioritised
    
    booster_strategy_vaccine_type,     # options: "Moderna","Pfizer","AstraZeneca","Johnson & Johnson","Sinopharm","Sinovac"  
    
    vaccination_history_FINAL_local = vaccination_history_FINAL,
    pop_setting_LOCAL = pop_setting
){
  
  ##### SETUP ###################################################################
  if (booster_strategy_start_date <= min(max(vaccination_history_TRUE$date),Sys.Date())){ 
    warning ('Your hypothetical vaccine campaign start date needs to be in the future!')
  }
  if (!(booster_strategy_vaccine_type %in% c("Moderna","Pfizer","AstraZeneca","Johnson & Johnson","Sinopharm","Sinovac"))){
    stop('pick a valid vaccine type, or check your spelling!')
  }
  if (booster_prev_dose_ceiling>max(vaccination_history_FINAL_local$dose)){booster_prev_dose_ceiling=max(vaccination_history_FINAL_local$dose)}
  
  vaccination_history_FINAL_local = vaccination_history_FINAL_local %>% 
    filter(date<booster_strategy_start_date)
  #_______________________________________________________________________________
  
  
  
  #####(1/4) Calculate the eligible population ###################################
  #sum all doses delivered by dose, type, risk/age group
  if (8 %in% unique(vaccination_history_FINAL_local$dose)){
    eligible_pop =  vaccination_history_FINAL_local %>% 
      group_by(dose,vaccine_type,risk_group,age_group,FROM_vaccine_type,FROM_dose) %>%
      summarise(eligible_individuals = sum(doses_delivered_this_date) , .groups = 'keep')
  } else{
    eligible_pop =  vaccination_history_FINAL_local %>% 
      group_by(dose,vaccine_type,risk_group,age_group,FROM_vaccine_type ) %>%
      summarise(eligible_individuals = sum(doses_delivered_this_date), .groups = 'keep')
  }
  
  #remove double counted, i.e., don't count first doses if they have received a second dose
  workshop_eligible_pop = eligible_pop %>% filter(dose == max(eligible_pop$dose))
  for (d in 2:max(eligible_pop$dose)){
    remove = eligible_pop %>% 
      ungroup() %>%
      filter(dose == d) %>%
      rename(complete_vax = eligible_individuals) %>%
      mutate(vaccine_type = FROM_vaccine_type) %>%
     # select(vaccine_type,risk_group,age_group,complete_vax) %>%
      group_by(vaccine_type,risk_group,age_group) %>%
      summarise(complete_vax = sum(complete_vax), .groups = "keep")
    
    if (nrow(remove)>0){
      this_dose = eligible_pop %>%
        filter(dose == (d-1)) %>%
        group_by(dose,vaccine_type,risk_group,age_group) %>%
        summarise(eligible_individuals = sum(eligible_individuals), .groups = 'keep') %>%
        left_join(remove, by = c('age_group','vaccine_type','risk_group')) %>%
        mutate(eligible_individuals = case_when(
          is.na(complete_vax) == FALSE~ eligible_individuals - complete_vax,
          TRUE ~ eligible_individuals,
        )) %>%
        select(-complete_vax)
    }
    workshop_eligible_pop = rbind(workshop_eligible_pop,this_dose)
  }
  eligible_pop = workshop_eligible_pop
  
  if (nrow(eligible_pop[eligible_pop$dose == 8,])>0){
    remove = eligible_pop  %>%
      ungroup() %>%
      filter(dose == 8) %>%
      select(-vaccine_type,-dose) %>%
      rename(boosted_vax = eligible_individuals,
             dose = FROM_dose, 
             vaccine_type = FROM_vaccine_type)
    
    if (nrow(remove)>0){
      eligible_pop = eligible_pop %>% 
        left_join(remove, by = c('age_group','vaccine_type','risk_group','dose')) %>%
        mutate(eligible_individuals = case_when(
          is.na(boosted_vax) ~ eligible_individuals, #this shouldn't be triggered
          TRUE ~ eligible_individuals - boosted_vax,
        )) %>%
        select(-boosted_vax)
    }
  }
  
  eligible_pop = eligible_pop  %>%
    filter(
      eligible_individuals > 0 &
        risk_group %in% booster_delivery_risk_group &
        ((dose >= booster_prev_dose_floor & vaccine_type != "Johnson & Johnson") | (dose >= (booster_prev_dose_floor-1) & vaccine_type == "Johnson & Johnson")) &
        ((dose <= booster_prev_dose_ceiling & vaccine_type != "Johnson & Johnson")| (dose <= (booster_prev_dose_ceiling-1) & vaccine_type == "Johnson & Johnson")) &
        age_group %in% booster_age_groups
    )
  
  #collapse dose == 8
  eligible_pop = eligible_pop %>%
    group_by(dose,vaccine_type,risk_group,age_group) %>%
    summarise(eligible_individuals = sum(eligible_individuals), .groups = 'keep')
  
  if (nrow(eligible_pop) == 0){
    warning('no one is eligible for this additional booster')
    return()
  }
  if (booster_prev_dose_floor>1){
    if (round(sum(eligible_pop$eligible_individuals)) != 
        round(sum(vaccination_history_FINAL_local$doses_delivered_this_date[
          (
            (vaccination_history_FINAL_local$dose == booster_prev_dose_floor & vaccination_history_FINAL_local$vaccine_type != "Johnson & Johnson") |
            (vaccination_history_FINAL_local$dose == booster_prev_dose_floor & vaccination_history_FINAL_local$vaccine_type == "Johnson & Johnson" & vaccination_history_FINAL_local$vaccine_type != vaccination_history_FINAL_local$FROM_vaccine_type) |
            (vaccination_history_FINAL_local$dose == booster_prev_dose_floor - 1 & vaccination_history_FINAL_local$vaccine_type == "Johnson & Johnson")
          ) &
          vaccination_history_FINAL_local$age_group %in% booster_age_groups &
          vaccination_history_FINAL_local$risk_group %in% booster_delivery_risk_group
          ])
          -sum(vaccination_history_FINAL_local$doses_delivered_this_date[
            (
              (vaccination_history_FINAL_local$dose == booster_prev_dose_ceiling + 1 & vaccination_history_FINAL_local$vaccine_type != "Johnson & Johnson") |
              (vaccination_history_FINAL_local$dose == booster_prev_dose_ceiling + 1 & vaccination_history_FINAL_local$vaccine_type == "Johnson & Johnson" & vaccination_history_FINAL_local$vaccine_type != vaccination_history_FINAL_local$FROM_vaccine_type) |
              (vaccination_history_FINAL_local$dose == booster_prev_dose_ceiling + 1 - 1 & vaccination_history_FINAL_local$vaccine_type == "Johnson & Johnson")
            ) &
            vaccination_history_FINAL_local$age_group %in% booster_age_groups &
            vaccination_history_FINAL_local$risk_group %in% booster_delivery_risk_group
          ])
          )){
      warning('eligible pop not lining up')
    }
  } else{
    if (sum(eligible_pop$eligible_individuals) != 
        sum(vaccination_history_FINAL_local$doses_delivered_this_date[(vaccination_history_FINAL_local$dose == booster_prev_dose_floor) &
                                                                vaccination_history_FINAL_local$age_group %in% booster_age_groups &
                                                                vaccination_history_FINAL_local$risk_group %in% booster_delivery_risk_group]) -
        sum(vaccination_history_FINAL_local$doses_delivered_this_date[(vaccination_history_FINAL_local$dose == booster_prev_dose_ceiling + 1) &
                                                                      vaccination_history_FINAL_local$age_group %in% booster_age_groups &
                                                                      vaccination_history_FINAL_local$risk_group %in% booster_delivery_risk_group])){
      warning('eligible pop not lining up')
    }
  }

  #_______________________________________________________________________________
  
  
  
  #####(2/4) Prioritisation ######################################################
  eligible_pop$priority = 1
  if (booster_prioritised_risk == "Y"){
    eligible_pop$priority[eligible_pop$risk_group == "general_public"] = eligible_pop$priority[eligible_pop$risk_group == "general_public"] + 1
  }
  if (unique(is.na(booster_prioritised_age) == FALSE)){
    eligible_pop$priority[! eligible_pop$age_group %in% booster_prioritised_age] = eligible_pop$priority[! eligible_pop$age_group %in% booster_prioritised_age] + 1
  }
  #_______________________________________________________________________________
  
  

  #####(3/4) Distribute between days #############################################
  rollout_doses_per_day = booster_rollout_percentage_pop/100 * sum(pop_setting_LOCAL$pop)
  rollout_days = ceiling(min(sum(eligible_pop$eligible_individuals),booster_dose_supply)/rollout_doses_per_day)
  #booster_strategy_start_date
 
  VA =  eligible_pop %>% mutate(doses_left = eligible_individuals)
  priority_num = 1
  highest_priority = max(VA$priority)

  booster_delivery_outline = data.frame()
  
  for (day in 1:rollout_days){
    
    avaliable = rollout_doses_per_day
    if (day == rollout_days){avaliable = sum(eligible_pop$eligible_individuals)- sum(booster_delivery_outline$doses_delivered_this_date)}

    while(round(avaliable,digits=2)>0 & priority_num <= highest_priority){
      
      if(sum(VA$doses_left[VA$priority == priority_num])>0){ 
        #i.e., while we still have doses to deliver in this priority group
        
        workshop_doses = min(sum(VA$doses_left[VA$priority == priority_num]),
                             avaliable)
        #either deliver max capacity or number left in this group, whichever is fewer
        
        VA_pt = VA #snapshot
        
        priority_group = VA %>% filter(priority == priority_num)
        
        for (i in 1:nrow(priority_group)){
          this_dose = priority_group$dose[i]
          this_vaccine_type = priority_group$vaccine_type[i]
          this_risk_group = priority_group$risk_group[i]
          this_age_group = priority_group$age_group[i]
          
          this_prop = priority_group$doses_left[i]/sum(priority_group$doses_left)
          
          row = data.frame(date = booster_strategy_start_date + day - 1,
                           vaccine_type = booster_strategy_vaccine_type,
                           dose = this_dose + 1,
                           doses_delivered_this_date = workshop_doses * this_prop,
                           age_group = this_age_group,                           
                           risk_group = this_risk_group,
                           FROM_vaccine_type = this_vaccine_type,
                           FROM_dose = this_dose,
                           schedule = "booster"
                           )
          booster_delivery_outline = rbind(booster_delivery_outline,row)
          
          VA$doses_left[VA$age_group == this_age_group & VA$dose == this_dose & VA$vaccine_type == this_vaccine_type & VA$risk_group == this_risk_group] = 
            VA$doses_left[VA$age_group == this_age_group & VA$dose == this_dose & VA$vaccine_type == this_vaccine_type & VA$risk_group == this_risk_group] - workshop_doses * this_prop
                
        }
        
        avaliable = avaliable - workshop_doses
        
        
      } else if (round(sum(VA$doses_left[VA$priority == priority_num]),digits=2)==0){
        priority_num = priority_num+1
        priority_group = as.character(unique(VA$age_group[VA$priority == priority_num]))
      } else{
        if (round(sum(VA$doses_left[VA$priority == priority_num]),digits=2)<0){
          stop('negative doses left, reconsider!')
        }
      }
    } #<end while loop>
  }
  
  ### formating booster_delivery_outline to align with vaccination_history_TRUE
  booster_delivery_outline = booster_delivery_outline %>%
    mutate(
           vaccine_mode = case_when(
             vaccine_type == 'Pfizer' ~ 'mRNA',
             vaccine_type == 'Moderna' ~ 'mRNA',
             vaccine_type == 'AstraZeneca' ~ 'viral_vector',
             vaccine_type == 'Sinopharm' ~ 'viral_inactivated',
             vaccine_type == 'Sinovac' ~ 'viral_inactivated',
             vaccine_type == 'Johnson & Johnson' ~ 'viral_vector'
           ),
           coverage_this_date = NA #shouldn't be used anyway
    ) 
  
  #CHECK #########################################
  #Checking all doses delivered
  if (round(sum(booster_delivery_outline$doses_delivered_this_date)) != round(min(sum(eligible_pop$eligible_individuals),booster_dose_supply))) { #if not all eligible individuals vaccinated
    stop('not all booster doses delivered')
  }
  
  #################################################
  ggplot(booster_delivery_outline) + geom_point(aes(x=date,y=doses_delivered_this_date,color=as.factor(age_group),shape=as.factor(FROM_vaccine_type)))
  
 return(booster_delivery_outline)

}
#_______________________________________________________________________________