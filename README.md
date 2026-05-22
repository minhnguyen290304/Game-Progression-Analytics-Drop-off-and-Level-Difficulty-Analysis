# 🎮 Game Progression Analytics: Drop-off & Level Difficulty Analysis

## 🎯 Project Overview
This project provides an end-to-end analysis of player gameplay behavior using game telemetry data collected from gameplay events.

The main objective is to transform raw gameplay logs into actionable insights by:
- Cleaning and reconstructing gameplay data  
- Analyzing player progression and retention behavior  
- Identifying difficulty spikes and frustration levels  
- Building an interactive dashboard for gameplay analytics  

---

## 🚀 Key Accomplishments
- **Data Processing:** Cleaned and processed **116,000+ gameplay event records** in SQL Server, handling duplicates, missing values, and progression reconstruction  
- **Gameplay Analytics:** Developed multiple retention and difficulty metrics including drop-off rate, fail rate, retry behavior, and average playtime analysis  
- **Dashboard Development:** Built an interactive **Power BI dashboard** visualizing player progression funnels, difficulty spikes, retention behavior, and gameplay segmentation  

---

## 🛠️ Tech Stack
- **Database:** Microsoft SQL Server (T-SQL)  
- **Data Processing:** Data Cleaning, Window Functions, CTEs, Gameplay Progression Reconstruction  
- **Visualization:** Power BI Desktop  

---

## 📁 Dataset Description

The dataset contains gameplay telemetry events collected from players during gameplay sessions.

### Main Features
- `user_id` — Player identifier  
- `event_timestamp` — Gameplay event timestamp  
- `event_name` — Gameplay event type (`level_start`, `level_end`)  
- `level` — Current gameplay level  
- `is_success` — Win/Loss result  
- `time_played` — Gameplay duration  
- `session_id` — Gameplay session identifier  
- `country` — Player region  
- `device_category` — Device type  
- `operating_system` — Operating system  
- `app_version` — Game version  

---

## 📂 Data Pipeline

### 1. Data Cleaning & Reconstruction (SQL)

The raw dataset contained:
- Duplicate gameplay events  
- Missing values (`NULL`)  
- Scientific notation formatting issues (`E+`)  
- Ambiguous session-user mappings  
- Missing progression information  

The cleaning process included:
- Removing duplicate rows  
- Restoring corrupted `BIGINT` values  
- Reconstructing missing `user_id` values using `session_id` and gameplay timelines  
- Inferring missing `level` values using gameplay progression logic  
- Handling missing `is_success` and `time_played` using gameplay behavior statistics  

### Example: Duplicate Removal using `ROW_NUMBER()`
```sql
WITH duplicate_rows AS (

    SELECT *,
    
        ROW_NUMBER() OVER (
            PARTITION BY
                user_id,
                event_timestamp,
                level
            ORDER BY (SELECT NULL)
        ) AS rn

    FROM dbo.game_events

)

DELETE
FROM duplicate_rows
WHERE rn > 1;
```

---

## 📊 Gameplay Analytics

### Player Drop-off Analysis
Multiple definitions of drop-off were developed:
- Next-Level Drop-off  
- Session-Ending Drop-off  
- Fail-Based Drop-off  

### Level Difficulty Metrics
The project analyzed level difficulty using:
- Fail Rate  
- Average Retries  
- Average Playtime  
- Drop-off Rate  

---

## 📊 Data Visualization (Power BI)

The Power BI dashboard includes:

### 📌 EDA Dashboard
- Gameplay event distribution  
- Device & country segmentation  
- Player progression overview  

### 📌 Drop-off Analysis
- Retention funnel  
- Drop-off rate by level  
- Churn behavior visualization  

### 📌 Difficulty Analysis
- Fail rate trends  
- Retry behavior analysis  
- Difficulty spike detection  
- Gameplay complexity visualization  

---

## 📊 Key Insights
- Certain levels showed unusually high fail rates and retry counts, indicating potential difficulty spikes  
- Some levels generated high drop-off rates despite low fail rates, suggesting pacing or engagement issues  
- Gameplay behavior varied significantly across devices and operating systems  
- Most unfinished gameplay sessions were associated with simultaneous missing `time_played` and `is_success` values  

---

## 💡 Future Improvements
- Apply machine learning models for churn prediction  
- Build player segmentation and cohort analysis  
- Detect abnormal gameplay behavior automatically  
- Automate ETL and dashboard refresh pipelines  

---

## 📌 Project Highlights
- End-to-end workflow: **SQL → Data Cleaning → Analytics → Power BI Visualization**  
- Strong focus on gameplay telemetry reconstruction and behavioral analytics  
- Business-oriented insights for player retention and level balancing  
- Interactive dashboard for gameplay progression and difficulty monitoring  
