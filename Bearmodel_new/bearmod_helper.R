library(lubridate)

source("bearmod_fx.R")

#' Devuelve los indices de la tabla de curvas por region
#' 
#' @param patNames Lista con los nombres de las regiones (patches)
#' @return Lista con todos los indices de datos que encontraremos en la tabla all_spread que devuelve la simulacion
#' 
getIndices = function(patNames) {
  paste0(rep(c("inf_", "rec_", "exp_", "sus_"), each=length(patNames)), patNames)
}

#' Ejecuta varias simulaciones del modelo y obtiene las curvas promedio de cada región y totales
#' 
#' @param pat_locator
#' @param movement_date
#' @param input_dates
#' @param params
#' @param num_runs
#' @return 
#' 
runModel = function(pat_locator, movement_data, input_dates, params, num_runs = 10) {
  
  ## Lee los parametros
  exposepd <- params$exposepd;
  if (is.null(exposepd))  {
    exposepd <- 5.1
    print(paste0("Using default value for expose period: ", exposepd))
  }
  
  recover <- params$recrate;
  if (is.null(recover))  {
    recover <- 1/12
    print(paste0("Using default value for recover rate: ", recover))
  }
  if(is.numeric(recover)) {
    recover <- data.frame(date = input_dates,recrate = recover)
  }
  
  exposerate <- params$exposerate;
  if (is.null(exposerate)) {
    exposerate <- 2.68/6
    print(paste0("Using default value for expose rate: ", exposerate))
  }

  prop_reported <- params$prop_reported;
  if (is.null(prop_reported)) {
    prop_reported <- 1
    print(paste0("Using default value for reported fraction: ", prop_reported))
  }
  if(is.numeric(prop_reported)) {
    prop_reported <- data.frame(date = input_dates,prop = prop_reported)
  }
  
  ## Inicializa datos de patches a partir de la tabla de movilidad
  patNames <<- pat_locator$patNames  
  patIDs <<- pat_locator$patIDs
  NPat <<- length(patNames)
  
  patnInf <- pat_locator$nInf / prop_reported$prop[1]
  patnExp <- pat_locator$nExp / prop_reported$prop[1]
  
  ## No se especifica reduccion de movilidad
  relative_move_data <- data.frame()
  
  ## Inicializa la población y realiza la primera simulacion
  HPop = InitiatePop(pat_locator,patnInf,patnExp)
  HPop_update2 = runSim(HPop,pat_locator,relative_move_data,movement_data,input_dates,recover,exposerate,exposepd,exposed_pop_inf_prop = 0, TSinday = 1)
  print(paste0("Run # ",1))
  
  epidemic_curve = HPop_update2$epidemic_curve
  all_spread = HPop_update2$all_spread
  
  curve_indices = "inf"
  all_spread_indices = getIndices(patNames)
  
  ## Ejecuta N simulaciones
  for (run in 2:num_runs){
    HPop_update2 = runSim(HPop,pat_locator,relative_move_data,movement_data, input_dates,recover,exposerate,exposepd,exposed_pop_inf_prop = 0, TSinday = 1)
    print(paste0("Run # ",run))
    
    epidemic_curve[, curve_indices] = epidemic_curve[, curve_indices] + HPop_update2$epidemic_curve[, curve_indices]
    all_spread[, all_spread_indices] = all_spread[, all_spread_indices] + HPop_update2$all_spread[, all_spread_indices]
  }

  ## Obtiene la media de todas las curvas y corrige con el factor de reportados
  epidemic_curve[, curve_indices] = epidemic_curve[, curve_indices] * prop_reported$prop /num_runs
  all_spread[, all_spread_indices] = all_spread[, all_spread_indices]  * prop_reported$prop / num_runs
  
  #save(results,file="results_ComVal_Mobility.RData")
  #   
  results = list()
  results$epidemic_curve = epidemic_curve
  results$all_spread = all_spread
  
  results
}


#' Dado un intervalo de fechas, rellena en una tabla todas las entradas correspondientes a los dias que
#' estan vacios, utilizando los datos del ultimo dia que tuviera algun valor.
#' 
#' @param input_dates Lista de fechas que deben figurar en la tabla
#' @param table Tabla de datos con una columna "date" que indica las fechas. Se pueden dar como datos de tipo
#' fecha, o como un valor numerico indicando el desplazamiento de dias respecto a la fecha inicial. En el ultimo caso,
#' el valor `1` corresponderia a la primera fecha de `input_dates`, y el valor `n` a `input_dates[n]`. 
#' @return Tabla `table` completada con entradas para todas las fechas de `input_dates`, y en la que los
#' valores numericos de la columna `date` se habran sustituido por las fechas de `input_dates`.
#' 
fillDates = function(input_dates, table) {
  num_dates = length(input_dates)
  result = data.frame()
  
  # Si se dan fecha absolutas, se transforman a dias de desplazamiento respecto a la fecha inicial
  if(is.Date(table$date)) {
    offset = table$date - input_dates[1] + 1
    table$date = offset
  }
  
  # Como patron inicial toma la ultima fecha anterior a la primera fecha de input_dates, o la primera fecha
  # de la tabla si no hubiese ninguna anterior
  first_date = min(table$date)
  previous_rows = subset(milestones, date<=1)
  if(nrow(previous_rows) > 0) {
    first_date = max(previous_rows$date)
  }
  day_pattern = subset(table, date==first_date)
  
  for (day in 1:num_dates) {
    # Obtiene las entradas de la tabla original para la fecha "day"
    daily_entries = subset(table, date==day)
    if(nrow(daily_entries) > 0) {
      # Si existen datos en la tabla original para la fecha, los toma como patron
      day_pattern = daily_entries
    } else {
      # En caso contrario, utiliza el ultimo patron guardado actualizando su fecha
      day_pattern$date = day
    }
    result = rbind(result, day_pattern)
  }
  
  # Transforma la columna numérica de fecha a las fecha reales
  result$date = input_dates[1] + result$date - 1
  
  result
}


plotAllPatches = function(table, patNames, col="inf", milestones=NULL, real_data=NULL) {
  par(mfrow=c(1, 1))
  
  columns = paste0(col, "_", patNames)
  total = rowSums(table[, columns])

  plot(table$dates, total, type="l", col="black", ylim=c(0,max(total)), xlab = "date", ylab = col)

  if(!is.null(milestones)) {
    for(i in 1:nrow(milestones)) {
      abline(v=milestones$date[i], col='blue', lty=1)
    }
  }

  if(!is.null(real_data)) {
    print(real_data)
    lines(as.Date(real_data$dates), real_data$inf, type="l", col="black", lty=2)
  }
  
  cl <- rainbow(length(columns))
  for (i in 1:length(columns)) {
    lines(table$dates, table[, columns[i]], col=cl[i], type="l")
  }
  legend("topright", col=c("black", cl), legend=c("Total", as.character(patNames)),  lty=1)
  
}

plotCurves = function(table, patNames) {
  
  par(mfrow=c(2, 2))
  
  total_inf = rowSums(table[, paste0("inf_", patNames)])
  total_exp = rowSums(table[, paste0("exp_", patNames)])
  total_rec = rowSums(table[, paste0("rec_", patNames)])
  total_sus = rowSums(table[, paste0("sus_", patNames)])
  
  plot(table$dates, total_inf, col="red", type='l', 
       xlab="date", ylab="population", ylim = c(0, max(total_sus)), main="Comunidad Valenciana")
  #abline(v=c(which(social_distancing_date==input_dates)), col='blue', lty=1)
  lines(table$dates, total_exp, col="light blue", lty=1)
  lines(table$dates, total_rec, col="green", lty=2)
  lines(table$dates, total_sus, col="magenta", lty=3)
  legend("left", legend=c("infectious", "exposed", "recovered", "susceptible"), 
         col=c("blue", "red", "green", "magenta"), lty=c(1, 1, 2, 3), cex=0.7)
  
  
  for (patch in patNames) {
    ymax = max(table[,getIndices(patch)])
    plot(table$dates, table[,paste0("exp_", patch)], col="red", type='l', 
         xlab="date", ylab="population", ylim = c(0, ymax), main=patch)
    lines(table$dates, table[,paste0("exp_", patch)], col="light blue", lty=1)
    lines(table$dates, table[,paste0("rec_", patch)], col="green", lty=2)
    lines(table$dates, table[,paste0("sus_", patch)], col="magenta", lty=3)
    legend("left", legend=c("infectious", "exposed", "recovered", "susceptible"), 
           col=c("blue", "red", "green", "magenta"), lty=c(1, 1, 2, 3), cex=0.7)
  }
  
}