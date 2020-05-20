library("leaflet")
library("shiny")

#Define your path
path<-"/home/cg2020/cg2020forto/shinyapp_project"

#Load environments (when you deploy to shinyapp.io)
source("www/token_mapbox.R")
load("www/leaflet_project.RData")

function(input, output, session) {
  output$map <- renderLeaflet({leaflet_project})
}



