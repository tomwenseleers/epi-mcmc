library("deSolve")
system("R CMD SHLIB model-agec.cpp")
dyn.load("model-agec.so")

InvalidDataOffset <- 10000
Initial <- 1

G <- 4.7
Tinc1 <- 3
Tinc2 <- 1
y.died_rate <- 0.0009
o.died_rate <- 0.03
a1 <- 1/Tinc1
a2 <- 1/Tinc2
gamma <- 1/((G - (Tinc1 + Tinc2)) * 2)
ifr.reduction <- 0.3
ifr.reduction.offset <- as.numeric(as.Date("2020/7/1") - dstartdate)

calcGammaProfile <- function(mean, sd)
{
    scale = sd^2 / mean
    shape = mean / scale
    
    kbegin = max(0, ceiling(mean - sd * 3))
    kend = max(kbegin + 1, floor(mean + sd * 3))

    result = NULL
    result$kbegin = -kend
    result$kend = -kbegin
    result$values = numeric(result$kend - result$kbegin)
    i = 1
    for (k in kbegin:kend) {
        result$values[i] = pgamma(k-0.5, shape=shape, scale=scale) -
            pgamma(k+0.5, shape=shape, scale=scale)
        i = i + 1
    }

    result$values = result$values / sum(result$values)
    result$values = rev(result$values)

    result
}

convolute <- function(values, i1, i2, profile)
{
    filter(values, profile$values, method="convolution", sides=1)[(i1 + profile$kend):(i2 + profile$kend)]
}

hospProfile <- calcGammaProfile
diedProfile <- calcGammaProfile

calculateModel <- function(params, period)
{
    betay0 <- params[1]
    betao0 <- params[2]
    betayo0 <- params[3]
    betay1 <- params[4]
    betao1 <- params[5]
    betayo1 <- params[6]
    betay2 <- params[7]
    betao2 <- params[8]
    betayo2 <- params[9]
    yhosp_rate <- params[10]
    yhosp_latency <- params[11]
    ydied_latency <- params[12]
    ohosp_rate <- params[13]
    ohosp_latency <- params[14]
    odied_latency <- params[15]
    t0_morts <- params[16]
    t0o <- params[17]
    HLsd <- params[18]
    DLsd <- params[19]
    t3o <- params[20] ## start of increase, 6 June
    betay3 <- params[21]
    betao3 <- params[22]
    betayo3 <- params[23]
    t4o <- params[24] ## end of increase, 6 Juli
    betay4 <- params[25]
    betao4 <- params[26]
    betayo4 <- params[27]
    betay5 <- betay4 ## new lockdown, 27 Juli
    betao5 <- betao4
    betayo5 <- betayo4
    t6o <- params[28]
    betay6 <- params[29] ## end of lockdown transition 27 Juli + t6o
    betao6 <- params[30]
    betayo6 <- params[31]

    ## convolution profile to infer hospitalisation count
    y.hosp_cv_profile = hospProfile(yhosp_latency, HLsd)
    o.hosp_cv_profile = hospProfile(ohosp_latency, HLsd)
    y.died_cv_profile = diedProfile(ydied_latency, DLsd)
    o.died_cv_profile = diedProfile(odied_latency, DLsd)

    padding = max(-y.hosp_cv_profile$kbegin, -y.died_cv_profile$kbegin,
                  -o.hosp_cv_profile$kbegin, -o.died_cv_profile$kbegin) + 1

    state <- NULL

    state$y.S <- rep(y.N - Initial, padding + period)
    state$y.E1 <- rep(Initial, padding + period)
    state$y.E2 <- rep(0, padding + period)
    state$y.I <- rep(0, padding + period)
    state$y.R <- rep(0, padding + period)
    state$y.hosp <- rep(0, padding + period)
    state$y.deadi <- rep(0, padding + period)

    state$o.S <- rep(o.N, padding + period)
    state$o.E1 <- rep(0, padding + period)
    state$o.E2 <- rep(0, padding + period)
    state$o.I <- rep(0, padding + period)
    state$o.R <- rep(0, padding + period)
    state$o.hosp <- rep(0, padding + period)
    state$o.deadi <- rep(0, padding + period)

    state$Re <- rep(0, padding + period)
    state$Rt <- rep(0, padding + period)
    state$y.Re <- rep(0, padding + period)
    state$o.Re <- rep(0, padding + period)

    state$i <- padding + 1
    
    parms <- c(Ny = y.N, No = o.N,
               a1 = a1, a2 = a2, gamma = gamma,
               t0 = 1E10, t1 = 1E10, t2 = 1E10,
               betay0 = betay0, betao0 = betao0, betayo0 = betayo0,
               betay1 = betay1, betao1 = betao1, betayo1 = betayo1,
               betay2 = betay2, betao2 = betao2, betayo2 = betayo2,
               t3 = 1E10, betay3 = betay3, betao3 = betao3, betayo3 = betayo3,
               t4 = 1E10, betay4 = betay4, betao4 = betao4, betayo4 = betayo4,
               t5 = 1E10, betay5 = betay5, betao5 = betao5, betayo5 = betayo5,
               t6 = 1E10, betay6 = betay6, betao6 = betao6, betayo6 = betayo6)

    Y <- c(Sy = y.N - Initial, E1y = Initial, E2y = 0, Iy = 0, Ry = 0,
           So = o.N, E1o = 0, E2o = 0, Io = 0, Ro = 0)

    times <- (padding + 1):(padding + period)

    out <- ode(Y, times, func = "derivs", parms = parms,
               dllname = "model-agec",
               initfunc = "initmod", nout = 4, outnames = c("Re", "Rt", "y.Re", "o.Re"))

    state$y.S[(padding + 1):(padding + period)] = out[,2]
    state$o.S[(padding + 1):(padding + period)] = out[,7]

    s2 <- convolute(state$y.S, padding + 1, padding + period, y.died_cv_profile)
    state$y.died[(padding + 1):(padding + period)] = (y.N - s2) * y.died_rate

    s2 <- convolute(state$o.S, padding + 1, padding + period, o.died_cv_profile)
    state$o.died[(padding + 1):(padding + period)] = (o.N - s2) * o.died_rate

    state$died = state$y.died + state$o.died

    data_offset = InvalidDataOffset

    lds <- which(state$died > t0_morts)
    if (length(lds) > 0) {
        data_offset <- lds[1] - lockdown_offset

        t2 <- data_offset + lockdown_offset + lockdown_transition_period
        t3 <- t2 + t3o
        t4 <- t3 + t4o

        t5 <- data_offset + d5        
        t6 <- t5 + t6o

        parms <- c(Ny = y.N, No = o.N,
                   a1 = a1, a2 = a2, gamma = gamma,
                   t0 = data_offset + lockdown_offset + t0o,
                   t1 = data_offset + lockdown_offset + max(t0o, 0),
                   t2 = t2,
                   betay0 = betay0, betao0 = betao0, betayo0 = betayo0,
                   betay1 = betay1, betao1 = betao1, betayo1 = betayo1,
                   betay2 = betay2, betao2 = betao2, betayo2 = betayo2,
                   t3 = t3, betay3 = betay3, betao3 = betao3, betayo3 = betayo3,
                   t4 = t4, betay4 = betay4, betao4 = betao4, betayo4 = betayo4,
                   t5 = t5, betay5 = betay5, betao5 = betao5, betayo5 = betayo5,
                   t6 = t6, betay6 = betay6, betao6 = betao6, betayo6 = betayo6)

        out <- ode(Y, times, func = "derivs", parms = parms,
                   dllname = "model-agec",
                   initfunc = "initmod", nout = 4, outnames = c("Re", "Rt", "y.Re", "o.Re"))
    }

    state$y.S[(padding + 1):(padding + period)] = out[,2]
    state$y.E[(padding + 1):(padding + period)] = out[,3] + out[,4]
    state$y.I[(padding + 1):(padding + period)] = out[,5]
    state$y.R[(padding + 1):(padding + period)] = out[,6]
    state$o.S[(padding + 1):(padding + period)] = out[,7]
    state$o.E[(padding + 1):(padding + period)] = out[,8]
    state$o.I[(padding + 1):(padding + period)] = out[,9] + out[,10]
    state$o.R[(padding + 1):(padding + period)] = out[,11]
    state$Re[(padding + 1):(padding + period)] = out[,12]
    state$Rt[(padding + 1):(padding + period)] = out[,13]
    state$y.Re[(padding + 1):(padding + period)] = out[,14]
    state$o.Re[(padding + 1):(padding + period)] = out[,15]

    s1 <- convolute(state$y.S, padding + 1, padding + period, y.hosp_cv_profile)
    state$y.hosp[(padding + 1):(padding + period)] = (y.N - s1) * yhosp_rate
    state$y.hospi <- c(state$y.hosp[1], diff(state$y.hosp))
    
    s2 <- y.N - convolute(state$y.S, padding + 1, padding + period, y.died_cv_profile)
    s2i <- c(s2[1], diff(s2))
    state$y.deadi[(padding + 1):(padding + period)] = s2i * y.died_rate
    if (data_offset != InvalidDataOffset) {
        t <- data_offset + ifr.reduction.offset
        state$y.deadi[(t + 1):(padding + period)] =
            state$y.deadi[(t + 1):(padding + period)] * (1 - ifr.reduction)
    }
    state$y.died = cumsum(state$y.deadi)

    s1 <- convolute(state$o.S, padding + 1, padding + period, o.hosp_cv_profile)
    state$o.hosp[(padding + 1):(padding + period)] = (o.N - s1) * ohosp_rate
    state$o.hospi <- c(state$o.hosp[1], diff(state$o.hosp))
    
    s2 <- o.N - convolute(state$o.S, padding + 1, padding + period, o.died_cv_profile)
    s2i <- c(s2[1], diff(s2))
    state$o.deadi[(padding + 1):(padding + period)] = s2i * o.died_rate
    if (data_offset != InvalidDataOffset) {
        t <- data_offset + ifr.reduction.offset
        state$o.deadi[(t + 1):(padding + period)] =
            state$o.deadi[(t + 1):(padding + period)] * (1 - ifr.reduction)
    }
    state$o.died = cumsum(state$o.deadi)

    state$padding <- padding
    state$offset <- data_offset

    state
}

transformParams <- function(params)
{
    params
}

invTransformParams <- function(posterior)
{
    posterior$Tinf <- 1/gamma

    posterior$y.Rt0 = posterior$betay0 / gamma
    posterior$o.Rt0 = posterior$betao0 / gamma
    posterior$yo.Rt0 = posterior$betayo0 / gamma

    posterior$y.Rt1 = posterior$betay1 / gamma
    posterior$o.Rt1 = posterior$betao1 / gamma
    posterior$yo.Rt1 = posterior$betayo1 / gamma

    posterior$y.Rt2 = posterior$betay2 / gamma
    posterior$o.Rt2 = posterior$betao2 / gamma
    posterior$yo.Rt2 = posterior$betayo2 / gamma

    posterior$y.Rt3 = posterior$betay3 / gamma
    posterior$o.Rt3 = posterior$betao3 / gamma
    posterior$yo.Rt3 = posterior$betayo3 / gamma
    
    posterior$y.Rt4 = posterior$betay4 / gamma
    posterior$o.Rt4 = posterior$betao4 / gamma
    posterior$yo.Rt4 = posterior$betayo4 / gamma

    posterior$y.Rt6 = posterior$betay6 / gamma
    posterior$o.Rt6 = posterior$betao6 / gamma
    posterior$yo.Rt6 = posterior$betayo6 / gamma

    posterior
}

calcNominalState <- function(state)
{
    state$hosp <- state$y.hosp + state$o.hosp
    state$died <- state$y.died + state$o.died
    state$hospi <- state$y.hospi + state$o.hospi
    state$deadi <- state$y.deadi + state$o.deadi

    state
}

## log likelihood function for fitting this model to observed data:
##   y.dhospi, o.dhospi, y.dmorti, o.dmorti
calclogp <- function(params) {
    betay0 <- params[1]
    betao0 <- params[2]
    betayo0 <- params[3]
    betay1 <- params[4]
    betao1 <- params[5]
    betayo1 <- params[6]
    betay2 <- params[7]
    betao2 <- params[8]
    betayo2 <- params[9]
    yhosp_rate <- params[10]
    yhosp_latency <- params[11]
    ydied_latency <- params[12]
    ohosp_rate <- params[13]
    ohosp_latency <- params[14]
    odied_latency <- params[15]
    t0_morts <- params[16]
    t0o <- params[17]
    HLsd <- params[18]
    DLsd <- params[19]
    t3o <- params[20]
    betay3 <- params[21]
    betao3 <- params[22]
    betayo3 <- params[23]
    t4o <- params[24]
    betay4 <- params[25]
    betao4 <- params[26]
    betayo4 <- params[27]
    betay5 <- betay4 ## new lockdown, 27 Juli
    betao5 <- betao4
    betayo5 <- betayo4
    t6o <- params[28]
    betay6 <- params[29] ## end of lockdown transition 27 Juli + t6o
    betao6 <- params[30]
    betayo6 <- params[31]

    logPriorP <- 0
    
    logPriorP <- logPriorP + dnorm(t0o, mean=0, sd=10, log=T)
    logPriorP <- logPriorP + dnorm(lockdown_offset + lockdown_transition_period + t3o, mean=d3, sd=10, log=T)
    logPriorP <- logPriorP + dnorm(lockdown_offset + lockdown_transition_period + t3o + t4o, mean=d4, sd=10, log=T)
    logPriorP <- logPriorP + dnorm(t6o, mean=G, sd=3, log=T)
    logPriorP <- logPriorP + dnorm(betay0 - betay1, mean=0, sd=2*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betao0 - betao1, mean=0, sd=2*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betayo0 - betayo1, mean=0, sd=2*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betay1 - betay2, mean=0, sd=2*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betao1 - betao2, mean=0, sd=2*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betayo1 - betayo2, mean=0, sd=2*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betay2 - betay3, mean=0, sd=0.5*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betao2 - betao3, mean=0, sd=0.5*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betayo2 - betayo3, mean=0, sd=0.5*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betay3 - betay4, mean=0, sd=0.5*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betao3 - betao4, mean=0, sd=0.5*gamma, log=T)
    logPriorP <- logPriorP + dnorm(betayo3 - betayo4, mean=0, sd=0.5*gamma, log=T)
    logPriorP <- logPriorP + dnorm(HLsd, mean=5, sd=1, log=T)
    logPriorP <- logPriorP + dnorm(DLsd, mean=5, sd=1, log=T)
    logPriorP <- logPriorP + dnorm(ydied_latency, mean=21, sd=4, log=T)
    logPriorP <- logPriorP + dnorm(odied_latency, mean=21, sd=4, log=T)

    logPriorP <- logPriorP + dnorm(betay6, mean=0.6, sd=0.2, log=T)
    logPriorP <- logPriorP + dnorm(betao6, mean=0.22, sd=0.2, log=T)
    logPriorP <- logPriorP + dnorm(betayo6, mean=0.26, sd=0.2, log=T)

    logPriorP
}

calclogl <- function(params, x) {
    state <<- calculateModel(params, FitTotalPeriod)

    if (state$offset == InvalidDataOffset)
        state$offset = 1

    ##    loglLD <- dnbinom(total_deaths_at_lockdown, mu=pmax(0.1, mort_lockdown_threshold),
    ##                      size=mort_nbinom_size, log=T)

    dstart <- state$offset
    dend <- state$offset + length(y.dhospi) - 1

    if (dend > length(state$y.hospi)) {
        ##print("=========================== Increase FitTotalPeriod ===================")
        dend <- length(state$y.hospi)
        dstart <- dend - length(y.dhospi) + 1
    }

    di <- y.dhospi

    if (dstart < 1) {
        ##print("=========================== Increase Padding ? ===================")
        dstart <- 1
        dend <- dstart + length(y.dhospi) - 1
    }

    y.loglH <- sum(dnbinom(y.dhospi[1:(d.reliable.cases-1)],
                           mu=pmax(0.1, state$y.hospi[dstart:(dstart + d.reliable.cases)]),
                           size=hosp_nbinom_size1, log=T)) +
               sum(dnbinom(y.dhospi[d.reliable.cases:length(y.dhospi)],
                           mu=pmax(0.1, state$y.hospi[(dstart + d.reliable.cases + 1):dend]),
                           size=hosp_nbinom_size2, log=T))

    o.loglH <- sum(dnbinom(o.dhospi[1:(d.reliable.cases-1)],
                           mu=pmax(0.1, state$o.hospi[dstart:(dstart + d.reliable.cases)]),
                           size=hosp_nbinom_size1, log=T)) +
               sum(dnbinom(o.dhospi[d.reliable.cases:length(o.dhospi)],
                           mu=pmax(0.1, state$o.hospi[(dstart + d.reliable.cases + 1):dend]),
                           size=hosp_nbinom_size2, log=T))

    dstart <- state$offset
    dend <- state$offset + length(y.dmorti) - 1

    if (dend > length(state$y.deadi)) {
        ##print("=========================== Increase FitTotalPeriod ===================")
        dend <- length(state$y.deadi)
        dstart <- dend - length(y.dmorti) + 1
    }

    if (dstart < 1) {
        ##print("=========================== Increase Padding ? ===================")
        dstart <- 1
        dend <- dstart + length(y.dmorti) - 1
    }

    y.loglD <- sum(dnbinom(y.dmorti,
                           mu=pmax(0.01, state$y.deadi[dstart:dend]),
                           size=mort_nbinom_size, log=T))

    o.loglD <- sum(dnbinom(o.dmorti,
                           mu=pmax(0.01, state$o.deadi[dstart:dend]),
                           size=mort_nbinom_size, log=T))

    it <<- it + 1

    result <- y.loglH + o.loglH + y.loglD + o.loglD
    
    if (it %% 1000 == 0) {
        print(params)
	print(c(it, result))
        state <<- calcNominalState(state)
	graphs()
    }

    result
}

fit.paramnames <- c("betay0", "betao0", "betayo0",
                    "betay1", "betao1", "betayo1",
                    "betay2", "betao2", "betayo2",
                    "y.HR", "y.HL", "y.DL",
                    "o.HR", "o.HL", "o.DL",
                    "t0_morts", "t0o",
                    "HLsd", "DLsd",
                    "t3o", "betay3", "betao3", "betayo3",
                    "t4o", "betay4", "betao4", "betayo4",
                    "t6o", "betay6", "betao6", "betayo6")
keyparamnames <- c("betay0", "betao0", "betayo0", "betay1", "betao1", "betayo1")
fitkeyparamnames <- keyparamnames

init <- c(3.6 * gamma, 3.6 * gamma, 3.6 * gamma,
          2.0 * gamma, 2.0 * gamma, 2.0 * gamma,
          0.8 * gamma, 0.8 * gamma, 0.8 * gamma,
          0.05, 10, 21,
          0.05, 10, 21,
          total_deaths_at_lockdown, -1, 5, 5,
          d3 - lockdown_offset - lockdown_transition_period, 0.8 * gamma, 0.8 * gamma, 0.8 * gamma,
          d4 - d3, 0.8 * gamma, 0.8 * gamma, 0.8 * gamma,
          G, 0.8 * gamma, 0.8 * gamma, 0.8 * gamma)

print(init)

df_params <- data.frame(name = fit.paramnames,
                        min = c(2 * gamma, 2 * gamma, 2 * gamma,
                                1 * gamma, 1 * gamma, 1 * gamma,
                                0.2 * gamma, 0.2 * gamma, 0.2 * gamma,
                                0.001, 5, 10,
                                0.001, 5, 10,
                                0, -30, 2, 2,
                                60, 0.2 * gamma, 0.2 * gamma, 0.2 * gamma,
                                10, 0.2 * gamma, 0.2 * gamma, 0.2 * gamma,
                                3, 0.2 * gamma, 0.2 * gamma, 0.2 * gamma),
                        max = c(8 * gamma, 8 * gamma, 8 * gamma,
                                5 * gamma, 5 * gamma, 5 * gamma,
                                2 * gamma, 2 * gamma, 2 * gamma,
                                1, 25, 50,
                                1, 25, 50,
                                max(dmort[length(dmort)] / 10, total_deaths_at_lockdown * 10),
                                30, 9, 9,
                                90, 3 * gamma, 3 * gamma, 3 * gamma,
                                50, 3 * gamma, 3 * gamma, 3 * gamma,
                                12, 1.5 * gamma, 1.5 * gamma, 1.5 * gamma),
                        init = init)
