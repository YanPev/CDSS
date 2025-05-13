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
  mutate(fullname = paste(name, lastname))

db$datetime <- as.POSIXct(db$datetime)

# Load LOINC dictionary
loinc_dict <- read_csv("Loinc.csv", show_col_types = FALSE) %>%
  select(loinc = LOINC_NUM, description = COMPONENT)

ui <- fluidPage(
  tags$head(
    tags$style(HTML("body { background-color: pink; }"))
  ),
  titlePanel("CDSS System - Part A"),
  tabsetPanel(
    tabPanel("View History",
             fluidRow(
               column(4,
                      selectizeInput("patient_name", "Patient First Name",
                                     choices = unique(db$name),
                                     selected = NULL,
                                     options = list(
                                       placeholder = 'Start typing a name...',
                                       maxOptions = 10,
                                       create = FALSE
                                     )),
                      textInput("loinc_code", "LOINC Code (optional)", value = ""),
                      dateInput("from_date", "From Date", value = Sys.Date() - 5),
                      dateInput("to_date", "To Date", value = Sys.Date() + 1),
                      timeInput("from_time", "From Time", value = strptime("00:00", "%H:%M")),
                      timeInput("to_time", "To Time", value = strptime("23:59", "%H:%M")),
                      actionButton("show_history", "Show History")
               ),
               column(8,
                      h4("Patient History"),
                      dataTableOutput("history_table")
               )
             )
    ),
    tabPanel("Update Measurement",
             sidebarLayout(
               sidebarPanel(
                 selectizeInput("update_name", "Patient First Name",
                                choices = unique(db$name),
                                selected = NULL,
                                options = list(
                                  placeholder = 'Start typing a name...',
                                  maxOptions = 10,
                                  create = FALSE
                                )),
                 textInput("update_loinc", "LOINC Code"),
                 dateInput("update_date", "Measurement Date"),
                 timeInput("update_time", "Measurement Time"),
                 numericInput("new_value", "New Value", value = NA),
                 actionButton("update_button", "Update Measurement")
               ),
               mainPanel(
                 verbatimTextOutput("update_result")
               )
             )
    ),
    tabPanel("Delete Measurement",
             sidebarLayout(
               sidebarPanel(
                 selectizeInput("delete_name", "Patient First Name",
                                choices = unique(db$name),
                                selected = NULL,
                                options = list(
                                  placeholder = 'Start typing a name...',
                                  maxOptions = 10,
                                  create = FALSE
                                )),
                 textInput("delete_loinc", "LOINC Code"),
                 dateInput("delete_date", "Date"),
                 timeInput("delete_time", "Time"),
                 actionButton("delete_button", "Delete Measurement")
               ),
               mainPanel(
                 verbatimTextOutput("delete_result")
               )
             )
    ),
    tabPanel("LOINC Dictionary",
             sidebarLayout(
               sidebarPanel(
                 selectizeInput("loinc_lookup", "Search LOINC Code",
                                choices = unique(loinc_dict$loinc),
                                selected = NULL,
                                options = list(
                                  placeholder = 'Start typing a LOINC code...',
                                  maxOptions = 10,
                                  create = FALSE
                                )),
                 actionButton("lookup_button", "Search Code")
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
  
  # View History
  history_data <- eventReactive(input$show_history, {
    req(input$patient_name, input$from_date, input$to_date)
    
    from_dt <- ymd_hms(paste(input$from_date, format(input$from_time, "%H:%M:%S")))
    to_dt   <- ymd_hms(paste(input$to_date, format(input$to_time, "%H:%M:%S")))
    
    df <- rv$data %>%
      filter(name == input$patient_name,
             datetime >= from_dt,
             datetime <= to_dt)
    
    if (input$loinc_code != "") {
      df <- df %>% filter(loinc == input$loinc_code)
    }
    
    df <- df %>% left_join(loinc_dict, by = "loinc")
    
    cat(">>> View History Triggered <<<\n")
    cat("Patient:", input$patient_name, "\n")
    cat("LOINC:", input$loinc_code, "\n")
    cat("From:", from_dt, "To:", to_dt, "\n")
    cat("Rows returned:", nrow(df), "\n")
    
    df
  })
  
  output$history_table <- renderDataTable({
    validate(
      need(nrow(history_data()) > 0, "No results found. Please check your inputs.")
    )
    history_data()
  })
  
  # Update Measurement
  update_msg <- eventReactive(input$update_button, {
    req(input$update_name, input$update_loinc, input$update_date, input$update_time, input$new_value)
    
    dt_target <- ymd_hms(paste(input$update_date, format(input$update_time, "%H:%M:%S")))
    
    index <- which(name == input$update_name &
                     loinc == input$update_loinc &
                     datetime == dt_target)
    
    if (length(index) == 0) {
      "No matching measurement found to update"
    } else {
      rv$data$value[index] <- input$new_value
      paste("Value successfully updated to", input$new_value)
    }
  })
  
  output$update_result <- renderPrint({
    update_msg()
  })
  
  # Delete Measurement
  delete_msg <- eventReactive(input$delete_button, {
    req(input$delete_name, input$delete_loinc, input$delete_date, input$delete_time)
    
    dt_target <- ymd_hms(paste(input$delete_date, format(input$delete_time, "%H:%M:%S")))
    before_delete <- nrow(rv$data)
    
    rv$data <- rv$data %>%
      filter(!(name == input$delete_name &
                 loinc == input$delete_loinc &
                 datetime == dt_target))
    
    after_delete <- nrow(rv$data)
    
    if (after_delete < before_delete) {
      "Measurement successfully deleted"
    } else {
      "No matching measurement found to delete"
    }
  })
  
  output$delete_result <- renderPrint({
    delete_msg()
  })
  
  # LOINC Lookup
  loinc_result <- eventReactive(input$lookup_button, {
    req(input$loinc_lookup)
    loinc_dict %>%
      filter(loinc == input$loinc_lookup)
  })
  
  output$loinc_result <- renderTable({
    loinc_result()
  })
}

shinyApp(ui, server)