# Mental Health Clinic Operations and Patient Retention Analytics

## Project overview

This portfolio project analyzes the operations of a synthetic mental health clinic using MySQL and Tableau. The analysis connects patient activity, appointment attendance, therapist performance, billing, progress scores, and clinical concerns to support operational and retention-focused decision-making.

All patient, therapist, appointment, clinical, and billing records in this repository are synthetically generated. The project contains no real patient data or protected health information.

## Business questions

The project examines questions such as:

- How much revenue was billed, collected, or placed at risk?
- Which patients show elevated cancellation or no-show risk?
- How do completion rates and lost revenue vary across therapists?
- Which clinical concerns appear most frequently?
- Which concern pairs commonly occur together?
- How do appointment activity, revenue, and clinical intensity change over time?

## Dashboard Preview

<table>
  <tr>
    <td width="50%">
      <h3>Executive KPI Summary</h3>
      <a href="executive_kpi_summary.pdf">
        <img src="Executive%20KPI%20Summary.png" width="100%">
      </a>
    </td>
    <td width="50%">
      <h3>Patient Risk Dashboard</h3>
      <a href="patient_risk_dashboard.pdf">
        <img src="Patient%20Risk.png" width="100%">
      </a>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3>Therapist Performance Scorecard</h3>
      <a href="therapist_performance_scorecard.pdf">
        <img src="Therapist%20Performance%20Scorecard.png" width="100%">
      </a>
    </td>
    <td width="50%">
      <h3>Clinical Trends</h3>
      <a href="clinical_trends.pdf">
        <img src="Clinical%20Trends.png" width="100%">
      </a>
    </td>
  </tr>
</table>

## Tools

- MySQL
- SQL
- Tableau
- Data modeling
- Common table expressions
- Window functions
- Views
- Self-joins
- KPI reporting
- Dashboard development

## Repository structure

```text
mental-health-clinic-analytics/
├── README.md
├── sql/
│   ├── mental_health_clinic_database.sql
│   └── analysis_queries.sql
└── dashboards/
    ├── executive_kpi_summary.pdf
    ├── patient_risk_dashboard.pdf
    ├── therapist_performance_scorecard.pdf
    └── clinical_trends.pdf
```

## Database and SQL analysis

`mental_health_clinic_database.sql` contains the relational database structure and synthetic records used in the project.

`analysis_queries.sql` contains analytical queries and reusable views for areas including:

- Revenue and payment performance
- Patient retention and appointment behavior
- Patient risk segmentation
- Therapist utilization and completion rates
- Clinical concern frequency and comorbidity
- Monthly trends and operational KPIs

## Dashboards

### Executive KPI Summary

Provides a high-level view of billed revenue, collected revenue, revenue at risk, active and churned patients, average progress score, monthly revenue trends, insurance mix, and month-over-month growth.

### Patient Risk Dashboard

Segments patients into high-, medium-, and low-risk groups using missed-appointment behavior, then compares risk patterns by insurance type, referral source, and therapist.

### Therapist Performance Scorecard

Compares collected revenue, lost revenue, and appointment completion rates across therapists.

### Clinical Trends

Explores concern frequency, severity distribution, commonly co-occurring concerns, and changes in average concerns addressed per session over time.

## Key takeaways

- Appointment attendance and cancellations have a direct relationship with revenue exposure.
- Patient risk segmentation can help identify groups that may benefit from proactive retention efforts.
- Therapist-level completion and revenue metrics can support scheduling and capacity decisions.
- Clinical concern and comorbidity trends can support resource planning and service-line analysis.

## How to review the project

1. Open the SQL files in the `sql` folder to review the database design and analytical queries.
2. Open the PDF files in the `dashboards` folder to review the Tableau outputs.
3. Run the database script in MySQL before executing the analytical queries if you want to reproduce the analysis.

## Author

**Qihong Huang**  
Data Science graduate student
