### This function contains the system of ordinary differential equations (ODEs) for COVID-19 transmission

covidODE <- function(t, state, parameters){
  require(deSolve)
  
  with(as.list(c(state,parameters)),{
    
    J = num_age_groups
    T = num_vax_types
    D = num_vax_doses
    RISK = num_risk_groups
    
    A=RISK*J*(T*D+1) # +1 is unvax
    
    S=state[1:A]
    E=state[(A+1):(2*A)]
    I=state[(2*A+1):(3*A)]
    R=state[(3*A+1):(4*A)]
    
    dS = dE = dI = dR = dIncidence  <- numeric(length=A)
    dExposed_S = dExposed_R         <- numeric(length=J)
 
    tau =(rep(0,J)) 
    
    #calculating transmission to each age group
    for (i in 1:J){
      for (j in 1:J){
        
        total=0 #total in contact age j
        for(interval in 1:(num_disease_classes*RISK*(T*D+1))){
          total = total+state[j+(interval-1)*J] 
        }
        
        total_infected_mod = 0 #total infected in age j
        for (r in 1:RISK){
          total_infected_mod = total_infected_mod + I[j+(r-1)*A/RISK] #unvax
          for (t in 1:T){
            for (d in 1:D){
              B = j + J*(t+(d-1)*T)+(r-1)*A/RISK
              #total_infected_mod=total_infected_mod + (1-VE_onwards[t,d])*I[B]
              total_infected_mod=total_infected_mod + I[B]
            }
          }
        }
        tau[i]=tau[i]+contact_matrix[i,j]*(total_infected_mod*(lota*(1-gamma[j])+gamma[j]))/(total)
        
      }
      tau[i]=tau[i]*(1-NPI)*beta[i]*suscept[i]
      tau[i]=max(min(1,tau[i]),0) #transmission can not be more than 1 (100%)
    }
    
    #system of ODEs
    for (r in 1:RISK){
      for (i in 1:J){
        #unvaccinated
        unvax = i+(r-1)*A/RISK
        dS[unvax] = omega*R[unvax]  - tau[i]*S[unvax] 
        dE[unvax] = tau[i]*S[unvax] - lambda*E[unvax] + tau[i]*(1-rho)*R[unvax]
        dI[unvax] = lambda*E[unvax] - delta*I[unvax]
        dR[unvax] = delta*I[unvax]  - omega*R[unvax]  - tau[i]*(1-rho)*R[unvax]
        
        dIncidence[unvax] = lambda*E[unvax]
        dExposed_S[i] = tau[i]*S[i]
        dExposed_R[i] = tau[i]*(1-rho)*R[i]
        
        for (t in 1:T){
          for (d in 1:D){
            #B = i+J+(t-1)*J+(d-1)*J*T = i+J(1+(t-1)+(d-1)*T)
            B = i + J*(t+(d-1)*T)+(r-1)*A/RISK
            VE_step = VE$VE[VE$dose==d & 
                              VE$risk_group == risk_group_labels[r] &
                              VE$vaccine_type == vax_type_list[t] &
                              VE$age_group == age_group_labels[i]] 
            if (length(VE_step) == 0){ VE_step = 0 } #no VE calculated because doses not delivered for this t/d/i combination
            
            dS[B] = omega*R[B]              - tau[i]*(1-VE_step)*S[B] 
            dE[B] = tau[i]*(1-VE_step)*S[B] - lambda*E[B] + tau[i]*(1-VE_step)*(1-rho)*R[B]
            dI[B] = lambda*E[B]             - delta*I[B]
            dR[B] = delta*I[B]              - omega*R[B]  - tau[i]*(1-VE_step)*(1-rho)*R[B]
            
            dIncidence[B] = lambda*E[B] 
            dExposed_S[i] = dExposed_S[i] + tau[i]*(1-VE_step)*S[B] 
            dExposed_R[i] = dExposed_R[i] + tau[i]*(1-VE_step)*(1-rho)*R[B]
            
          }
        }
      }
    }
    
    dS = as.numeric(dS)
    dE = as.numeric(dE)
    dI = as.numeric(dI)
    dR = as.numeric(dR)
    
    list(c(dS,dE,dI,dR,dIncidence,dExposed_S,dExposed_R))  
  })
}


