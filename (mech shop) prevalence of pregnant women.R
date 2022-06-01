
#COMEBACK - should women be cycling in and out of this group?
#COMEBACK - * 3/4 to get women currently pregnant?  or 1/4 for third trimester? or * ~ 2 for all lactating women?
#COMEBACK - could be stochastic with confidence interval

### read in data
ASFR = read.csv("1_inputs/SLE_ASFR.csv",header=TRUE)
women_pop = read.csv(paste(rootpath,"inputs/pop_estimates_female.csv",sep=''),header=TRUE)


### plot ASFR
#View(ASFR)
ggplot(data=ASFR) + 
  geom_pointrange(aes(x=ASFR*100,y=AGE,xmin=LCI*100,xmax=UCI*100)) +
 # xlim(0,1) +
  xlab("Age-specific fertility ratio (%)") + 
  ylab("") + 
  labs(title="")


### calculate and plot female ratio estimates
#pop_setting_orig - colnames: age, country, population
#women_pop - colnames: age, country, population, population_thousands
women_pop = women_pop %>% rename(pop_women = population) %>% select(-population_thousands)
pop_together = pop_setting_orig %>% left_join(women_pop) %>%
  mutate(female_prop = pop_women/population) %>%
  select(-pop_women)
ggplot(data=pop_together) + 
  geom_point(aes(x=female_prop*100,y=age)) +
  xlim(0,100) +
  ylim(15,49)


### convert ASFR to whole-population values (apply female ratio estimates)
ASFR_labels = ASFR$AGE
ASFR_breaks = c(15,19,24,29,34,39,44,49)
pop_together = pop_together %>%
  mutate(agegroup_ASFR = cut(age,breaks = ASFR_breaks, include.lowest = T, labels = ASFR_labels)) %>%
  ungroup() %>%
  group_by(agegroup_ASFR) %>%
  mutate(ASFR_group_percent = population/sum(population),
         interim = ASFR_group_percent * female_prop) 
ASFR_group_ratios = aggregate(pop_together$interim, 
                              by=list(category= pop_together$agegroup_ASFR), FUN=sum)
colnames(ASFR_group_ratios) = c('AGE','female_prop')   

Pop_ASFR = ASFR %>% left_join(ASFR_group_ratios) %>%
  mutate(ASFR = ASFR * female_prop) %>%
  select(AGE,ASFR) %>%
  rename(agegroup_ASFR = AGE)
         

### adapt ASFR to model age groups         
pop_conversion = pop_setting_orig %>%
  mutate(agegroup_ASFR = cut(age,breaks = ASFR_breaks, include.lowest = T, labels = ASFR_labels),
         agegroup_MODEL = cut(age,breaks = age_groups, include.lowest = T, labels = age_group_labels)) %>%
  left_join(Pop_ASFR) %>%
  select(-agegroup_ASFR) %>%
  ungroup() %>% group_by(agegroup_MODEL) %>%
  mutate(agegroup_percent = population/sum(population),
         interim = agegroup_percent * ASFR) 
pop_conversion$interim[is.na(pop_conversion$interim)]=0
model_pregnancy_agegroups = aggregate(pop_conversion$interim, 
                              by=list(category= pop_conversion$agegroup_MODEL), FUN=sum)
colnames(model_pregnancy_agegroups) = c('age_group','prop')   


### save as output (see dummy version in risk_group.csv) 
#colnames: risk_group, age_group, prop, source
prevalence_pregnancy = model_pregnancy_agegroups %>% 
  mutate(risk_group = 'pregnant_women',
         source = 'DHS analysis + UN Pop prospects female ratio')
prevalence_pregnancy

save(prevalence_pregnancy, file = "1_inputs/prevalence_pregnancy.Rdata")



