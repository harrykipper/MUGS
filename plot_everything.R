library(ggplot2)
library(reshape2)
library(rgdal)
library(RColorBrewer)

my.colours <- brewer.pal(6, "Blues")
glasgow_bench<-readOGR("../../census/glasgow_microsim_pcode.shp")

version<-"0.2.6.8"
scale<-20

dta<-read.csv(paste0("spans-",version,"-scale_",scale,"-all.csv"))
zones<-read.csv(paste0("spans-",version,"-scale_",scale,"-zones.csv"), row.names = NULL)
colnames(zones)<-colnames(zones)[-1]
zones<-zones[-ncol(zones)]

dta<-dta[order(dta$city),]
dta$abdeRtAvg<-round(dta$meanAB/dta$meanDE,1)
dta$abdeRtMed<-round(dta$medAB/dta$medDE,1)


val<-c(unique(dta$a))
tol<-c(unique(dta$tolerance))
htol<-c(unique(dta$heteroph.tol))
init<-c(unique(dta$initial.prob))
equal<-c(levels(dta$equalinit))
random<-c(levels(dta$random))
walk<-c(levels(dta$walkability))
segregated<-c(levels(dta$segregated))
heter<-c(levels(dta$heterophily))

relevant<-c(1,14:17) # median - comment if you want to plot mean values
mn<-"med"
#relevant<-c(1,18:21) # mean - uncomment if you want to plot mean values
#mn<-"mean"

for(j in equal) {
  for(w in walk) {
    for(r in random){
      for (v in val){
        for (t in tol){
          for (ht in htol){
            for (h in heter) {
              for (s in segregated){
                ee<-""   # "Edinburgh effect"
                dist<-"actual"
                if(r=="true"){dist<-"random"}else{if(s=="true"){dist<-"segregated"}}
                if(h=="true"){phily<-"heterophily"}else{phily<-"homophily"}
                if(w=="true"){wlk<-"walk"}else{wlk<-"no_walk"}
                dat<-dta[dta$equalinit==j & dta$random==r & dta$walkability == w & 
                            dta$a==v & dta$tolerance==t & dta$heteroph.tol==ht & 
                            dta$heterophily==h & dta$segregated==s,]
                
                diff0<-NA
                diff1<-NA
                  
                ineq<-cbind(dat[c(1,ncol(dta))],rowSums(dat[14:17])/4)
                colnames(ineq)<-c("city","ineq","total")
              
                # Do we have the Edinburgh effect in this run?
                # The "Edinburgh Effect" is defined as a situation in which 
                # Edinburgh has the largest overall number of visits and
                # the lowest inequality between classes
                
                ## We now compare the Glasgow distribution with the Microsimulation
                glaval<-zones[zones$city=="glasgow" & zones$equalinit==j & zones$random==r & zones$walkability == w & 
                              zones$a==v & zones$tolerance==t & zones$heteroph.tol==ht & 
                              zones$heterophily==h & zones$segregated==s,]
                glaval<-glaval[c(1,ncol(glaval)-1)]
                qtl<-quantile(glaval$median)
                msm_qtl<-quantile(glasgow_bench$msim_bench)
                glaval$abm.qtl<-0
                glasgow_bench$msm_qtl<-0
                
                for(qq in rev(1:5)){glaval$abm.qtl<-ifelse(glaval$median<=qtl[qq],qq,glaval$abm.qtl)}
                for(qq in rev(1:5)){glasgow_bench$msm.qtl<-ifelse(glasgow_bench$msim_bench<=msm_qtl[qq],qq,glasgow_bench$msm.qtl)}
                
                colnames(glaval)<-c("code","abm.med","abm.qtl")
                bench<-merge(glasgow_bench@data,glaval,by="code")
                bench$diff<-abs(bench$msm.qtl-bench$abm.qtl)
                good<-nrow(bench[bench$diff==0,])
                diff0<-round(good/nrow(bench), digits=2)
                diff1<-round(((good + nrow(bench[bench$diff==1,]))/nrow(bench)), digits = 2)
                
                valid_geo<-merge(glasgow_bench,glaval,by="code")
                
                ttl<-paste0("v",version,"; scale = ",scale, "; ", phily, "; ",wlk,"; dist: ", dist, " ", ee)
                st<-(paste0("a = ",v,"; t = ",t, "; ht = ", ht, "; eqp = ", j, "; diff0 = ", diff0, "; diff1 = ", diff1))
                
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
                name<-paste0("mugs-",version,"-s",scale,"-",mn,"-",phily,"-equalp_",j,"-",dist,"-",wlk,"-a_",v,"-tolerance_",t,"-hTolerance_",ht,ee)
                
                
                ## Save the map
                png(paste0(name,"-map.png"), width = 640,height = 480)
                spplot(valid_geo, "abm.qtl", col.regions=my.colours, cuts=5, scales = list(draw=T))
                dev.off()
                
                ## Save the diagram
                p<-ggplot(data=dat,aes(x=city, y=visits, fill=class)) +
                  geom_bar(stat="identity", position = position_dodge()) + 
                  ggtitle(paste0(ttl,ee), subtitle=st) +
                  scale_x_discrete(labels=c(paste0(ineq[,1]," (",ineq[,2],")")))
                
                ggsave(paste0(name,".png"),width=6,height=4)
              }
            }
          }
        }
      }
    }
  }
}
