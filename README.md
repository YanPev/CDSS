
# CDSS Mini Project – Architecture and User Guide

_Last updated: 2025-05-14 06:35_

---

## 📐 Architecture Overview

```
             ┌─────────────────────────────┐
             │        User Interface       │
             │  SelectizeInput, TimeInput  │
             └────────────┬────────────────┘
                          │
               Receives user input
                          │
             ┌────────────▼────────────┐
             │        Shiny Server     │
             │ Query / Update / Delete│
             └────────────┬────────────┘
                          │
         Uses secure SQL with parameters
                          │
             ┌────────────▼────────────┐
             │     SQLite Database     │
             │       project_db        │
             └────────────┬────────────┘
                          │
            ← ← ← ← ← ← ← ▼ ← ← ← ← ← ← ←
      Excel (project_db.xlsx) + Loinc.csv
```

---

## 📘 User Guide

### Navigation
The app includes 4 tabs:
- **View History**
- **Update Measurement**
- **Delete Measurement**
- **LOINC Dictionary**

### 🔍 View History
1. Select patient by full name.
2. Optionally enter a LOINC code.
3. Choose date & time range.
4. Click “Show History” to display the records.

### ✍️ Update Measurement
1. Select full name.
2. Enter LOINC code, date, time, and new value.
3. Click “Update” to overwrite the closest prior record.

### ❌ Delete Measurement
1. Select patient, LOINC code, date, and time.
2. Click “Delete”.
3. The most recent matching measurement on that date is removed.

### 📚 LOINC Dictionary
1. Select a LOINC code.
2. Click “Search Code” to view full description.

---

## 🧠 DSS Dimensions

| Dimension              | Description                                                                 |
|------------------------|-----------------------------------------------------------------------------|
| **1. Clinical Domain** | Based on LOINC-coded clinical parameters like WBC, PaCO2.                   |
| **2. Target User**     | Designed for clinical staff to review and manipulate patient measurements. |
| **3. Decision Type**   | Supports data validation and real-time decision making.                    |
| **4. Intervention Timing** | Changes and actions are immediate during use.                        |
| **5. Knowledge Use**   | Integrates LOINC for clinical code interpretation.                          |
| **6. Workflow Integration** | Can embed into larger EHR/CDSS systems.                              |
| **7. Information Delivery** | Visual tabular views, time filtering, code lookup.                   |

---

## ✅ Example Use Case

> A doctor reviews WBC trends and notices an anomaly. Using the update tab, they fix a wrongly recorded value. Then, they review previous entries to confirm accuracy.

---
