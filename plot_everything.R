library(ggplot2)
library(reshape2)

version<-"0.2.6.7"
scale<-40

dta<-read.csv(paste0("spans-",version,"-scale_",scale,"-all.csv"))
dta$abdeRtAvg<-round(dta$meanAB/dta$meanDE,1)
dta$abdeRtMed<-round(dta$medAB/dta$medDE,1)

val<-c(unique(dta$a))
tol<-c(unique(dta$tolerance))
init<-c(unique(dta$initial.prob))
equal<-c("true","false")
random<-equal
walk<-random
segregated<-random
heter<-equal

for(j in equal) {
  for(w in walk) {
    for(r in random){
      for (v in val){
        for (t in tol){
          for (h in heter) {
            for (s in segregated){
              dist<-"actual"
              if(r=="true"){dist<-"random"}else{if(s=="true"){dist<-"segregated"}}
              if(h=="true"){phily<-"hetherophily"}else{phily<-"homophily"}
              if(w=="true"){wlk<-"wlk"}else{wlk<-"nowlk"}
              dat<-dta[dta$equalinit==j & dta$random==r & dta$walkability == w & 
                         dta$a==v & dta$tolerance==t & dta$heterophily==h &
                         dta$segregated==s,]
              if(nrow(dat)>0){
                ineq<-dat[c(1,ncol(dta))]
                colnames(ineq)<-c("city","ineq")
                relevant<-c(1,13:16) # median - comment if you want to plot mean values
                mn<-"med"
                #relevant<-c(1,17:20) # mean - uncomment if you want to plot mean values
                #mn<-"mean"
                dat<-dat[relevant]
                colnames(dat)<-sub(mn,"",colnames(dat))
                dat<-melt(dat,id="city")
                colnames(dat)<-c("city","class","visits")
                p<-ggplot(data=dat,aes(x=city, y=visits, fill=class)) +
                  geom_bar(stat="identity", position =
                           position_dodge())+ggtitle(paste0("v",version," ", phily, "; a=",v,"; tol=",t, "; equalp=", j, "; ",wlk,"; ", dist))+
                  scale_x_discrete(labels=c(paste0(ineq[,1]," (",ineq[,2],")")))
                ggsave(paste0("mugs-",version,"-s",scale,"-",mn,"-",phily,"-equalp_",j,"-",dist,"-",wlk,"-a_",v,"-tolerance_",t,".png"),width=6,height=4)
              }
            }
          }
        }
      }
    }
  }
}
