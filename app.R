library(shiny)
library(readxl)
library(readr)
library(dplyr)
library(DT)
library(lubridate)
library(shinyTime)

# Load patient data
db <- read_excel("project_db.xlsx", sheet = 1) %>%
  rename(loinc = `LOINC-NUM`,
         value = Value,
         unit = Unit,
         datetime = `Valid start time`,
         name = `First name`,
         lastname = `Last name`) %>%
  mutate(fullname = paste(name, lastname))  # for display if needed

# Ensure POSIXct datetime
db$datetime <- as.POSIXct(db$datetime)

# Load LOINC dictionary
loinc_dict <- read_csv("Loinc.csv", show_col_types = FALSE) %>%
  select(loinc = LOINC_NUM, description = COMPONENT)

ui <- fluidPage(
  titlePanel("מערכת CDSS - חלק א"),
  tabsetPanel(
    tabPanel("צפייה בהיסטוריה",
             sidebarLayout(
               sidebarPanel(
                 textInput("patient_name", "שם המטופל"),
                 textInput("loinc_code", "קוד LOINC"),
                 dateInput("from_date", "מתאריך"),
                 dateInput("to_date", "עד תאריך"),
                 timeInput("from_time", "משעה", value = strptime("00:00", "%H:%M")),
                 timeInput("to_time", "עד שעה", value = strptime("23:59", "%H:%M"))
               ),
               mainPanel(
                 dataTableOutput("history_table")
               )
             )
    ),
    tabPanel("עדכון מדידה",
             sidebarLayout(
               sidebarPanel(
                 textInput("update_name", "שם המטופל"),
                 textInput("update_loinc", "קוד LOINC"),
                 dateInput("update_date", "תאריך המדידה"),
                 timeInput("update_time", "שעת המדידה"),
                 numericInput("new_value", "ערך חדש", value = NA)
               ),
               mainPanel(
                 verbatimTextOutput("update_result")
               )
             )
    ),
    tabPanel("מחיקת מדידה",
             sidebarLayout(
               sidebarPanel(
                 textInput("delete_name", "שם המטופל"),
                 textInput("delete_loinc", "קוד LOINC"),
                 dateInput("delete_date", "תאריך"),
                 timeInput("delete_time", "שעה")
               ),
               mainPanel(
                 verbatimTextOutput("delete_result")
               )
             )
    ),
    tabPanel("מילון LOINC",
             sidebarLayout(
               sidebarPanel(
                 textInput("loinc_lookup", "קוד LOINC לחיפוש")
               ),
               mainPanel(
                 tableOutput("loinc_result")
               )
             )
    )
  )
)

server <- function(input, output, session) {
  rv <- reactiveValues(data = db)
  
  output$history_table <- renderDataTable({
    req(input$patient_name, input$loinc_code)
    
    from_dt <- as.POSIXct(paste(input$from_date, format(input$from_time, "%H:%M")))
    to_dt <- as.POSIXct(paste(input$to_date, format(input$to_time, "%H:%M")))
    
    df <- rv$data %>%
      filter(name == input$patient_name,
             loinc == input$loinc_code,
             datetime >= from_dt & datetime <= to_dt)
    
    df <- df %>%
      left_join(loinc_dict, by = "loinc")
    
    datatable(df)
  })
  
  output$update_result <- renderPrint({
    req(input$update_name, input$update_loinc, input$update_date, input$update_time, input$new_value)
    
    dt_target <- as.POSIXct(paste(input$update_date, format(input$update_time, "%H:%M")))
    
    index <- which(rv$data$name == input$update_name &
                     rv$data$loinc == input$update_loinc &
                     rv$data$datetime == dt_target)
    
    if (length(index) == 0) {
      message <- "אין מדידה מתאימה לעדכון"
    } else {
      rv$data$value[index] <- input$new_value
      message <- paste("הערך עודכן בהצלחה ל-", input$new_value)
    }
    
    message
  })
  
  output$delete_result <- renderPrint({
    req(input$delete_name, input$delete_loinc, input$delete_date, input$delete_time)
    
    dt_target <- as.POSIXct(paste(input$delete_date, format(input$delete_time, "%H:%M")))
    before_delete <- nrow(rv$data)
    
    rv$data <- rv$data %>%
      filter(!(name == input$delete_name &
                 loinc == input$delete_loinc &
                 datetime == dt_target))
    
    after_delete <- nrow(rv$data)
    
    if (after_delete < before_delete) {
      "המדידה נמחקה בהצלחה"
    } else {
      "לא נמצאה מדידה למחיקה"
    }
  })
  
  output$loinc_result <- renderTable({
    req(input$loinc_lookup)
    loinc_dict %>%
      filter(loinc == input$loinc_lookup)
  })
}

shinyApp(ui, server)