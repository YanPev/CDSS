library(shiny)
library(readxl)
library(readr)
library(dplyr)
library(DT)
library(RSQLite)
library(lubridate)
library(shinyTime)

# Connect to SQLite DB
if (!file.exists("patient_db.sqlite")) {
  db_excel <- read_excel("project_db.xlsx") %>%
    rename(
      loinc = `LOINC-NUM`,
      value = Value,
      unit = Unit,
      datetime = `Valid start time`,
      name = `First name`,
      lastname = `Last name`
    ) %>%
    mutate(
      fullname = paste(name, lastname),
      datetime = as.numeric(as.POSIXct(datetime))  # store as UNIX timestamp
    )

  con <- dbConnect(SQLite(), "patient_db.sqlite")
  dbWriteTable(con, "project_db", db_excel, overwrite = TRUE)
  dbDisconnect(con)
}

# Load LOINC dictionary
loinc_dict <- read_csv("Loinc.csv", show_col_types = FALSE) %>%
  select(loinc = `LOINC_NUM`, loinc_name = COMPONENT)

# Reconnect for session
con <- dbConnect(SQLite(), "patient_db.sqlite")

ui <- fluidPage(
  tags$head(tags$style(HTML("body { background-color: pink; }"))),
  titlePanel("CDSS System"),
  tabsetPanel(
    tabPanel("View History",
             fluidRow(
               column(4,
                      selectizeInput("patient_fullname", "Patient Full Name",
                                     choices = NULL,
                                     options = list(placeholder = 'Start typing a name...')),
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
                 selectizeInput("update_fullname", "Patient Full Name", choices = NULL,
                                options = list(placeholder = 'Start typing a name...')),
                 textInput("update_loinc", "LOINC Code"),
                 dateInput("update_date", "Measurement Date"),
                 timeInput("update_time", "Measurement Time"),
                 numericInput("new_value", "New Value", value = NA),
                 actionButton("update_button", "Update Measurement")
               ),
               mainPanel(verbatimTextOutput("update_result"))
             )
    ),
    tabPanel("Delete Measurement",
             sidebarLayout(
               sidebarPanel(
                 selectizeInput("delete_fullname", "Patient Full Name", choices = NULL,
                                options = list(placeholder = 'Start typing a name...')),
                 textInput("delete_loinc", "LOINC Code"),
                 dateInput("delete_date", "Date"),
                 timeInput("delete_time", "Time"),
                 actionButton("delete_button", "Delete Measurement")
               ),
               mainPanel(verbatimTextOutput("delete_result"))
             )
    ),
    tabPanel("LOINC Dictionary",
             sidebarLayout(
               sidebarPanel(
                 selectizeInput("loinc_lookup", "Search LOINC Code",
                                choices = unique(loinc_dict$loinc),
                                options = list(placeholder = 'Start typing a LOINC code...')),
                 actionButton("lookup_button", "Search Code")
               ),
               mainPanel(tableOutput("loinc_result"))
             )
    )
  )
)

server <- function(input, output, session) {
  # Update patient fullname choices
  observe({
    fullnames <- dbGetQuery(con, "SELECT DISTINCT fullname FROM project_db")$fullname
    updateSelectizeInput(session, "patient_fullname", choices = fullnames, server = TRUE)
    updateSelectizeInput(session, "update_fullname", choices = fullnames, server = TRUE)
    updateSelectizeInput(session, "delete_fullname", choices = fullnames, server = TRUE)
  })

  # View history
  observeEvent(input$show_history, {
    tryCatch({
      from_dt <- as.numeric(as.POSIXct(paste0(input$from_date, " ", format(input$from_time, "%H:%M:%S"))))
      to_dt   <- as.numeric(as.POSIXct(paste0(input$to_date, " ", format(input$to_time, "%H:%M:%S"))))

      query <- "SELECT *, datetime(datetime, 'unixepoch') AS readable_time FROM project_db WHERE fullname = ? AND datetime BETWEEN ? AND ?"
      params <- list(input$patient_fullname, from_dt, to_dt)

      if (input$loinc_code != "") {
        query <- paste(query, "AND loinc = ?")
        params <- append(params, input$loinc_code)
      }

      df <- dbGetQuery(con, query, params = params)
      df$loinc_name <- loinc_dict$loinc_name[match(df$loinc, loinc_dict$loinc)]
      df <- df %>% mutate(datetime = readable_time) %>% select(-readable_time)

      output$history_table <- renderDataTable({
        if (nrow(df) == 0) {
          data.frame(Message = "No results found. Please check your inputs.")
        } else {
          df
        }
      })
    }, error = function(e) {
      output$history_table <- renderDataTable({
        data.frame(Error = e$message)
      })
    })
  })

  # Update measurement
  observeEvent(input$update_button, {
    dt_target <- as.numeric(as.POSIXct(paste0(input$update_date, " ", format(input$update_time, "%H:%M:%S"))))
    df <- dbGetQuery(con, "SELECT rowid, * FROM project_db WHERE fullname = ? AND loinc = ? AND datetime <= ?",
                     params = list(input$update_fullname, input$update_loinc, dt_target))
    if (nrow(df) == 0) {
      output$update_result <- renderPrint("No matching measurement found to update")
    } else {
      last_row <- df[which.max(df$datetime), ]
      dbExecute(con, "UPDATE project_db SET value = ? WHERE rowid = ?",
                params = list(input$new_value, last_row$rowid))
      output$update_result <- renderPrint(sprintf("Value successfully updated to %f", input$new_value))
    }
  })

  # Delete measurement
  observeEvent(input$delete_button, {
    dt_target <- as.numeric(as.POSIXct(paste0(input$delete_date, " ", format(input$delete_time, "%H:%M:%S"))))
    df <- dbGetQuery(con, "SELECT rowid, * FROM project_db WHERE fullname = ? AND loinc = ?",
                     params = list(input$delete_fullname, input$delete_loinc))
    df <- df[df$datetime == dt_target, ]
    if (nrow(df) == 0) {
      output$delete_result <- renderPrint("No matching measurement found to delete")
    } else {
      dbExecute(con, "DELETE FROM project_db WHERE rowid = ?", params = list(df$rowid[1]))
      output$delete_result <- renderPrint("Measurement successfully deleted")
    }
  })

  # LOINC lookup
  observeEvent(input$lookup_button, {
    result <- loinc_dict[loinc_dict$loinc == input$loinc_lookup, ]
    output$loinc_result <- renderTable(result)
  })
}

shinyApp(ui, server)
