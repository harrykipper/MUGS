library(ggplot2)
library(reshape2)
library(rgdal)
library(RColorBrewer)
library(gridExtra)
setwd("~/ownCloud/sphsu/neigh/results")
my.colours <- brewer.pal(6, "Blues")
glasgow_bench<-readOGR("../../census/glasgow_microsim_pcode.shp")

version<-"0.4.7"
scale<-30

dta<-read.csv(paste0("spans-",version,"-scale_",scale,"-all.csv"))
zones<-read.csv(paste0("spans-",version,"-scale_",scale,"-zones.csv"), row.names = NULL, stringsAsFactors=FALSE)
colnames(zones)<-colnames(zones)[-1]
zones<-zones[-ncol(zones)]

dta<-dta[order(dta$city),]
dta$abdeRtAvg<-round(dta$meanAB/dta$meanDE,1)
dta$abdeRtMed<-round(dta$medAB/dta$medDE,1)

val<-c(unique(dta$a))
valB<-c(unique(dta$b))
tol<-c(unique(dta$tolerance))
htol<-c(unique(dta$heteroph.tol))
init<-c(unique(dta$initial.prob))
equal<-c(levels(dta$equalinit))
random<-c(levels(dta$random))
walk<-c(levels(dta$walkability))
segregated<-c(levels(dta$segregated))
heter<-c(unique(dta$heterophily))
pull<-c(levels(dta$pull))

relevant<-c(1,15:18) # median - comment these two lines
mn<-"med"            # if you want to plot median values

#relevant<-c(1,19:22) # mean - uncomment these two lines 
#mn<-"mean"           # if you want to plot mean values

i<-0

for(j in equal) {
  for(w in walk) {
    for(r in random){
      for (v in val){
        for(bb in valB) {
          for (t in tol) {
            for (ht in htol){
              for (h in heter) {
                for (p in pull) {
                  for (s in segregated){
                    ee<-""   # "Edinburgh effect"
                    dist<-"actual"
                    pll<-""
                    if(r=="true"){dist<-"random"}else{if(s=="true"){dist<-"segregated"}}
                    if(w=="true"){wlk<-"walk"}else{wlk<-"no_walk"}
                    if(p=="true"){pll<-"pull"}
                    dat<-dta[dta$equalinit==j & dta$random==r & dta$walkability == w & 
                                dta$a==v & dta$b==bb & dta$tolerance==t & dta$heteroph.tol==ht & 
                                dta$heterophily==h & dta$segregated==s & dta$pull==p,]
                    
                    if (nrow(dat) > 0) {
                      
                      diff0<-NA
                      diff1<-NA
                      corr<-NA
                      
                      ineq<-cbind(dat[c(1,ncol(dta))],rowSums(dat[15:18])/4)
                      colnames(ineq)<-c("city","ineq","total")
   
                      ## We now compare the Glasgow distribution with the Microsimulation
                      glaval<-zones[zones$city=="glasgow" & zones$equalinit==j & zones$random==r & zones$walkability == w & 
                                    zones$a==v & zones$b==bb & zones$tolerance==t & zones$heteroph.tol==ht & 
                                    zones$heterophily==h & zones$segregated==s & zones$pull==p,]
                      glaval<-glaval[c(1,ncol(glaval)-1)]
                      qtl<-quantile(glaval$median)
                      msm_qtl<-quantile(glasgow_bench$msim_bench)
                      glaval$abm.qtl<-0
                      glasgow_bench$msm_qtl<-0
                  
                      for(qq in rev(1:5)){
                        glaval$abm.qtl<-ifelse(glaval$median<=qtl[qq],qq,glaval$abm.qtl)
                        glasgow_bench$msm.qtl<-ifelse(glasgow_bench$msim_bench<=msm_qtl[qq],qq,glasgow_bench$msm.qtl)
                      }
                    
                      colnames(glaval)<-c("code","abm.med","abm.qtl")
                      bench<-merge(glasgow_bench@data,glaval,by="code")
                      bench$diff<-abs(bench$msm.qtl-bench$abm.qtl)
                      good<-nrow(bench[bench$diff==0,])
                      diff0<-round(good/nrow(bench), digits=2)
                      diff1<-round(((good + nrow(bench[bench$diff==1,]))/nrow(bench)), digits = 2)
                      corr<-round(cor(bench$msim_bench,bench$abm.med),digits = 2)
                    
                      valid_geo<-merge(glasgow_bench,glaval,by="code")
                    
                      ttl<-paste0("v",version,"; s=",scale, "; h=", h, "; ", pll, "; ", wlk,"; dist: ", dist, " ", ee)
                      st<-(paste0("a=",v,"; b=",bb,"; t=",t, "; ht=", ht, "; eqp=", j, "; diff0=", diff0, "; diff1=", diff1,"; cor=", corr))
                    
                      # Do we have the Edinburgh effect in this run?
                      # We define the "Edinburgh Effect" as a situation in which, 
                      # while having a class gradient in visits to parks, Edinburgh 
                      # has the largest overall number of visits and the lowest 
                      # inequality between classes
                      
                      if(ineq[ineq$ineq==min(ineq$ineq),]$city=="edinburgh" & 
                         ineq[ineq$total==max(ineq$total),]$city=="edinburgh") 
                        {
                        ee<-"EE"
                        print("We have an Edinburgh effect!")
                        print(ttl)
                        print(st)
                      }
                    
                      ## Produce the dataset for diagrams 
                      dat<-dat[relevant]
                      colnames(dat)<-sub(mn,"",colnames(dat))
                      dat<-melt(dat,id="city")
                      colnames(dat)<-c("city","class","visits")
                      name<-paste0("mugs-",version,"-s",scale,"-",mn,"-",pll,"-equalp_",j,"-",dist,"-",wlk,"-a_",v,"b_",bb,"-t",t,"-hT",ht,"-h",h,ee)
                        
                      
                      ## Save the map
                      #p<-spplot(valid_geo, "abm.qtl", col.regions=my.colours, cuts=5, scales = list(draw=T))
                      #ggsave(paste0(name,"-map.png"),device="png",width=6,height=4)
                      
                    
                      ## Save the diagram
                      
                      assign(paste0("p",i),ggplot(data=dat,aes(x=city, y=visits, fill=class)) +
                             geom_bar(stat="identity", position = position_dodge()) + 
                             ggtitle(paste0(ttl,ee), subtitle=st) +
                             scale_x_discrete(labels=c(paste0(ineq[,1]," (",ineq[,2],")")))
                      )
                             
                    
                      #p<-ggplot(data=dat,aes(x=city, y=visits, fill=class)) +
                      #  geom_bar(stat="identity", position = position_dodge()) + 
                      #  ggtitle(paste0(ttl,ee), subtitle=st) +
                      #  scale_x_discrete(labels=c(paste0(ineq[,1]," (",ineq[,2],")")))
                      #  
                      ggsave(paste0(name,".png"),device="png",width=6,height=4)
                      i<-i+1
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
grid.arrange(p0,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14,p15,p16,p17,p18,p19,ncol = 3)
