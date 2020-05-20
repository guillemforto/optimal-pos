library("leaflet")
library("shiny")
library("shinythemes")

shinyUI(fluidPage(theme = shinytheme("flatly"), windowTitle = "Best Zones",
                  title=div(img(src="logo_tse.png", width = 100), "Our Final Project's App"),
                  
                  splitLayout(h5("Interactive map"),
                              bootstrapPage(div(class="outer",
                                                shiny::tags$style(type = "text/css", ".outer {position: fixed; top: 41px; left: 0; right: 0; bottom: 0; overflow: hidden; padding: 0}"),
                                                leafletOutput("map", width="100%", height="100%")
                              ))
                  ),
                  splitLayout(cellWidths=450,
                              sliderInput("competitors", "Adjusted p-value treshold",
                                          min=0, max=20, value=1, step=1, width=450)
                  )
))

