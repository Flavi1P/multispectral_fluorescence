library(tidyverse)
library(lubridate)
library(zoo)
library(patchwork)
library(stringr)


write_ctd_echo_df <- function(echo_path, ctd_path, prof, lag = 0, bouss){
  first <- readLines(ctd_path)
  start_line <- grep('END', first)
  
  hour_line <- first[grep('start_time', first)]
  start_time <- str_extract(hour_line, '[0-9]{2}:[0-9]{2}:[0-9]{2}')
  
  hr <- as.numeric(substr(start_time, 1,2))
  mn <- as.numeric(substr(start_time, 4,5))
  sc <- as.numeric(substr(start_time, 7,8))
  
  
  ctd <- read_table(ctd_path, 
                     col_names = FALSE, skip = start_line)
  
  if(bouss == 231){
    names(ctd) <- c('pres', 'time', 'temp', 'conductivity',
                    'sbeox0v', 'fluo_chl', 'flag') #la config a été changée sur cette campagne, car il y avait MOOSEGE en même temps
  }else{
    names(ctd) <- c('pres', 'time', 'temp', 'conductivity',
                    'sbeox0v', 'fluo_chl', 'upoly0', 'upoly1', 'potemp',
                    'sal00', 'sigma', 'sbeox_ml', 'sbeox_mm', 'flag')
    
  }
  

  
  if(prof == 'asc'){
    ctd_clean <- ctd[min(which(ctd$pres == max(ctd$pres))):min(which(ctd$pres == min(ctd$pres))),]
  }
  if(prof == 'desc'){
    ctd_clean <- ctd[1:min(which(ctd$pres == max(ctd$pres))),]
  }
  
  
  
  origin <- hr*3600 + mn* 60 + sc
  ctd_clean$time <- seconds_to_period(origin + ctd_clean$time)
  
  #ctd_clean <- ctd_clean[1:min(which(ctd_clean$pres < 2)),]
  
  ggplot(ctd_clean)+
    geom_path(aes(x = fluo_chl, y = -pres))
  
  t <- 0
  echo <- data.frame()
  if(bouss < 230){
    while(ncol(echo) != 24){
      echo <- read_table(echo_path, col_names = FALSE, skip = t)
      t <- t+1
    } 
  }else{
    echo <- read_table(echo_path, col_names = FALSE)
  }
  
  
  echo <- echo %>% filter(!is.na(X4))
  echo$X4 <- hms(echo$X4)
  echo$X4 <- echo$X4 - lag
  
  echo$X5 <- gsub(']', '', echo$X5)
  echo$X1 <- gsub('\\[', '', echo$X1)
  
  ctd_clean$second <- as.numeric(seconds(ctd_clean$time))
  echo$second <- as.numeric(seconds(echo$X4))
  
  echo <- filter(echo, second > min(round(ctd_clean$second)) & second < max(round(ctd_clean$second)))
  pres_eco <- approx(ctd_clean$second, ctd_clean$pres, xout = echo$second)
  
  echo$pres <- pres_eco$y
  find <- apply( echo, 1, paste, collapse = "-" )
  
  mf <- grep(440, find)
  flbb <- grep(695, find)
  
  if(bouss < 230){
    
    ecov2 <- grep('ECOV2', find)
    ecov2 <- echo[ecov2,]
    ecov2names <- c('FrameSync,Counter,
CHL HiGain(Counts),CHL LoGain(Counts),CHL LTC(Counts),CHL Raw(Counts),
Beta-700 HiGain(Counts),Beta-700 LoGain(Counts),Beta-700 LTC(Counts),Beta-700 Raw(Counts),
CHL2 HiGain(Counts),CHL2 LoGain(Counts),CHL2 LTC(Counts),CHL2 Raw(Counts),
FDOM HiGain(Counts),FDOM LoGain(Counts),FDOM LTC(Counts),FDOM Raw(Counts),
vMain(Volts)') %>% strsplit(',') %>% unlist()
    
    names(ecov2) <- c('day_name', 'month', 'day', 'time', 'year', ecov2names, 'second', 'pres')
  }
  
  
  echo_3x1m <- echo[mf,]
  flbb <- echo[flbb,]
  
  if(bouss < 230){
    echo_3x1m <- select(echo_3x1m, -X6, -X7, -X8, -X10, -X12, -(X14:X24))
    flbb <- select(flbb, -X6, -X7, -X8, -X10, -X12, -(X15:X24))
  }else{
    echo_3x1m <- select(echo_3x1m, -X6, -X7, -X8, -X10, -X12, -X14)
    flbb <- select(flbb, -X6, -X7, -X8,-X10, -X12)
  }
  
  
  
  names(echo_3x1m) <- c('day_name', 'month', 'day', 'time', 'year', 'fluo_440', 'fluo_470', 'fluo_532', 'second', 'pres')
  names(flbb) <- c('day_name', 'month', 'day', 'time', 'year', 'fluo_flbb', 'bb700', 'cdom', 'echov1', 'second', 'pres')
  
  if(bouss < 230){
    multiplex <- full_join(flbb, echo_3x1m) %>% left_join(select(ecov2, all_of(ecov2names), pres), by = 'pres') %>% janitor::clean_names()
    
  }else{
    multiplex <- full_join(flbb, echo_3x1m) %>% janitor::clean_names()
    
  }
  multiplex$time <- hms(multiplex$time)
  multiplex <- multiplex[which(!is.na(multiplex$time)),]
  
  
  
  full_df <- bind_rows(ctd_clean, multiplex)
  day_df <- unique(na.omit(full_df$day))
  month_df <- unique(na.omit(full_df$month))
  year_df <- unique(na.omit(full_df$year))
  full_df <- full_df %>% mutate(date = paste(day_df, month_df, year_df, sep = ' '),
                                day = day_df,
                                month = month_df,
                                year = year_df)
  
  return(full_df)
}

way <- 'asc'
prof_num <- 2
bouss <- 230

path_to_echo <- paste('Boussole/Data/raw/echo/b', bouss, '_', prof_num, '.txt', sep = '')
path_to_ctd <- paste('Boussole/Data/SBEMOOSE/Work/cnv/bous', bouss, '_0', prof_num, '.cnv', sep = '')

path_to_save <- paste('Boussole/Output/Data/b', bouss, '/b', bouss, '_', way, prof_num, '.csv', sep = '')

output_df <- write_ctd_echo_df(echo_path = path_to_echo,
                               ctd_path = path_to_ctd,
                               prof = way,
                               bouss = bouss)


# create all dataframe from all campains ----------------------------------

my_data_list <- list.files("Boussole/Data/SBEMOOSE/Work/cnv")
#my_data_list <- my_data_list[-str_detect(my_data_list, "bous223")]

bouss_numb <- unique(str_extract(my_data_list, "[0-9]{3}_[0-9]{2}")) %>% na.omit()
num_temp <- as.numeric(str_extract(bouss_numb, "[0-9]{3}"))

bouss_numb <- bouss_numb[num_temp > 224 & num_temp != 232]


for(i in bouss_numb){
  num_temp <- as.numeric(str_extract(i, "[0-9]{3}"))
  prof_temp <- str_extract(i, "[0-9]$")
  way <- c("asc", "desc")
  for(j in way){
    path_to_echo <- paste('Boussole/Data/raw/echo/b', num_temp, '_', prof_temp, '.txt', sep = '')
    path_to_ctd <- paste('Boussole/Data/SBEMOOSE/Work/cnv/bous', num_temp, '_0', prof_temp, '.cnv', sep = '')
    
    path_to_save <- paste('Boussole/Output/Data/b', num_temp, '/b', num_temp, '_', j, prof_temp, '.csv', sep = '')
    
    output_df <- write_ctd_echo_df(echo_path = path_to_echo,
                                   ctd_path = path_to_ctd,
                                   prof = j,
                                   bouss = num_temp)
    
      
      #####attention##################################
      ###########################################"
      write_csv(output_df, path_to_save)
  }
}
 

