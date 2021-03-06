####################
##
## Read data into dmort, dmorti, dhosp, dhospi:
##  dmort, dmorti: cumulative and incident deaths per day
##  dhosp, dhospi: cumulative and incident hospitalisations per day
##  dstartdate: first entry
##
####################

dstartdate <- as.Date("2020/3/10")

be.hosp <- read.csv(url("https://epistat.sciensano.be/Data/COVID19BE_HOSP.csv"))
##be.hosp <- read.csv("COVID19BE_HOSP.csv")
print(aggregate(be.hosp$NEW_IN, by=list(date=be.hosp$DATE), FUN=sum))
dhospi <- aggregate(be.hosp$NEW_IN, by=list(date=be.hosp$DATE), FUN=sum)$x
dbeds <- aggregate(be.hosp$TOTAL_IN, by=list(date=be.hosp$DATE), FUN=sum)$x
dicu <- aggregate(be.hosp$TOTAL_IN_ICU, by=list(date=be.hosp$DATE), FUN=sum)$x

## older data estimated from charts in older reports, missing in file
dhospi <- c(3, 12, 47, 50, 50, dhospi)
dbeds <- c(rep(NA, 5), dbeds)
dicu <- c(rep(NA, 5), dicu)

## remove latest data point, seems to be an incomplete day
## dhospi <- dhospi[1:(length(dhospi) - 1)]

dhosp <- cumsum(dhospi)

be.mort <- read.csv(url("https://epistat.sciensano.be/Data/COVID19BE_MORT.csv"))
##be.mort <- read.csv("COVID19BE_MORT.csv")
print(aggregate(be.mort$DEATHS, by=list(date=be.mort$DATE), FUN=sum))
dmorti <- aggregate(be.mort$DEATHS, by=list(date=be.mort$DATE), FUN=sum)$x

## remove two latest data point, may be incomplete because of WZC
dmorti <- dmorti[1:(length(dmorti) - 2)]
dmort <- cumsum(dmorti)

## all data series are now from 10/3

print(paste("last day morti: ", dstartdate + length(dmorti) - 1))

be.case <- read.csv(url("https://epistat.sciensano.be/Data/COVID19BE_CASES_AGESEX.csv"))
##be.case <- read.csv("COVID19BE_CASES_AGESEX.csv")
print(aggregate(be.case$CASES, by=list(date=be.case$DATE), FUN=sum))
dcasei <- aggregate(be.case$CASES, by=list(date=be.case$DATE), FUN=sum)$x

## also start from 10/3
dcasei <- dcasei[10:length(dcasei)]
## remove two latest data point, may be incomplete because of WZC
dcasei <- dcasei[1:(length(dcasei) - 2)]
dcase <- cumsum(dcasei)

#####################
## Population size
#####################

N <- 11.5E6
country_adjective <- "Belgian"

#####################
## Lockdown measures
#####################

## Date of lockdown phase (1)
lockdown_offset <- as.numeric(as.Date("2020/3/12") - dstartdate)

## over how many days the lockdown is estimated to have occurred
lockdown_transition_period <- 10

## how many deaths at date of lockdown
total_deaths_at_lockdown <- 5

d3 <- as.numeric(as.Date("2020/6/6") - dstartdate)
d4 <- as.numeric(as.Date("2020/7/6") - dstartdate)
d5 <- as.numeric(as.Date("2020/7/27") - dstartdate)
d6 <- as.numeric(as.Date("2020/8/17") - dstartdate)
d7 <- as.numeric(as.Date("2020/9/21") - dstartdate)
d8 <- as.numeric(as.Date("2020/10/9") - dstartdate)
d9 <- as.numeric(as.Date("2020/10/16") - dstartdate)
d10 <- as.numeric(as.Date("2020/10/28") - dstartdate)
##d12 <- as.numeric(as.Date("2020/11/16") - dstartdate)
d12 <- as.numeric(as.Date("2020/12/14") - dstartdate)

d.reliable.cases <- as.numeric(as.Date("2020/10/1") - dstartdate)
##d.reliable.cases <- as.numeric(as.Date("2020/7/1") - dstartdate)
d.reliable.hosp <- as.numeric(as.Date("2020/6/1") - dstartdate)
d.hosp.o1 <- as.numeric(as.Date("2020/6/22") - dstartdate)
d.hosp.o2 <- as.numeric(as.Date("2020/9/14") - dstartdate)
d.symp.cases <- as.numeric(as.Date("2020/10/21") - dstartdate)
symp.cases.factor <- 0.75
