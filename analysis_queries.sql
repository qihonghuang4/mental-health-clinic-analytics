-- ============================================================
-- Mental Health Clinic Operations & Patient Retention Analytics
-- SQL Analysis Queries
-- ============================================================
-- Skills demonstrated:
--   JOINs (INNER, LEFT, SELF), Subqueries, CTEs, Window Functions
--   (RANK, DENSE_RANK, ROW_NUMBER, LAG, SUM OVER, AVG OVER),
--   CASE WHEN, HAVING, GROUP BY, Views, Indexes, Aggregate Functions
-- ============================================================

USE mental_health_clinic;

-- ============================================================
-- REUSABLE VIEWS
-- ============================================================

-- View 1: Core patient-appointment-session join (used repeatedly)
CREATE OR REPLACE VIEW vw_patient_sessions AS
SELECT
    p.patientID,
    p.name AS patient_name,
    p.age,
    p.gender,
    p.insurance_type,
    p.referral_source,
    p.enrollment_date,
    t.therapistID,
    t.name AS therapist_name,
    t.specialty,
    t.session_fee,
    a.appointmentID,
    a.date AS appointment_date,
    a.status,
    sr.sessionID,
    sr.dateCompleted,
    sr.progress_score,
    at_tbl.frequency
FROM patient p
JOIN assigned_to at_tbl ON p.patientID = at_tbl.patientID
JOIN therapist t ON at_tbl.therapistID = t.therapistID
LEFT JOIN appointment a ON p.patientID = a.patientID
LEFT JOIN session_record sr ON a.appointmentID = sr.appointmentID;

-- View 2: Monthly revenue summary
CREATE OR REPLACE VIEW vw_monthly_revenue AS
SELECT
    DATE_FORMAT(b.billing_date, '%Y-%m') AS month,
    COUNT(b.billingID) AS total_sessions_billed,
    SUM(b.amount) AS gross_revenue,
    SUM(b.insurance_covered) AS insurance_revenue,
    SUM(b.patient_copay) AS copay_revenue,
    SUM(CASE WHEN b.payment_status = 'Paid' THEN b.amount ELSE 0 END) AS collected_revenue,
    SUM(CASE WHEN b.payment_status = 'Denied' THEN b.amount ELSE 0 END) AS denied_revenue,
    SUM(CASE WHEN b.payment_status = 'Pending' THEN b.amount ELSE 0 END) AS pending_revenue
FROM billing b
GROUP BY DATE_FORMAT(b.billing_date, '%Y-%m');


-- ============================================================
-- PILLAR 1: REVENUE & FINANCIAL HEALTH
-- ============================================================

-- Q1: Total revenue by therapist with ranking
-- Skills: CTE, Window Function (RANK), CASE WHEN, aggregate
SELECT
    t.therapistID,
    t.name,
    t.specialty,
    COUNT(DISTINCT sr.sessionID) AS total_sessions,
    SUM(b.amount) AS gross_revenue,
    SUM(CASE WHEN b.payment_status = 'Paid' THEN b.amount ELSE 0 END) AS collected_revenue,
    SUM(CASE WHEN b.payment_status = 'Denied' THEN b.amount ELSE 0 END) AS denied_revenue,
    ROUND(SUM(CASE WHEN b.payment_status = 'Paid' THEN b.amount ELSE 0 END) / SUM(b.amount) * 100, 2) AS collection_rate,
    RANK() OVER (ORDER BY SUM(b.amount) DESC) AS revenue_rank
FROM therapist t
JOIN appointment a ON t.therapistID = a.therapistID
JOIN session_record sr ON a.appointmentID = sr.appointmentID
JOIN billing b ON sr.sessionID = b.sessionID
GROUP BY t.therapistID, t.name, t.specialty
ORDER BY gross_revenue DESC;


-- Q2: Revenue lost to cancellations and no-shows (opportunity cost)
-- Skills: CTE, CASE WHEN, subquery
WITH cancellation_costs AS (
    SELECT
        t.therapistID,
        t.name,
        t.specialty,
        t.session_fee,
        COUNT(a.appointmentID) AS total_appointments,
        SUM(CASE WHEN a.status = 'Completed' THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN a.status = 'Canceled' THEN 1 ELSE 0 END) AS canceled,
        SUM(CASE WHEN a.status = 'No-show' THEN 1 ELSE 0 END) AS no_shows,
        SUM(CASE WHEN a.status IN ('Canceled', 'No-show') THEN t.session_fee ELSE 0 END) AS revenue_lost
    FROM therapist t
    JOIN appointment a ON t.therapistID = a.therapistID
    GROUP BY t.therapistID, t.name, t.specialty, t.session_fee
)
SELECT
    *,
    ROUND(revenue_lost / (total_appointments * session_fee) * 100, 2) AS pct_revenue_at_risk,
    RANK() OVER (ORDER BY revenue_lost DESC) AS loss_rank
FROM cancellation_costs
ORDER BY revenue_lost DESC;


-- Q3: Month-over-month revenue growth
-- Skills: Window Function (LAG), CTE
WITH monthly AS (
    SELECT
        month,
        gross_revenue,
        collected_revenue
    FROM vw_monthly_revenue
)
SELECT
    month,
    gross_revenue,
    collected_revenue,
    LAG(gross_revenue) OVER (ORDER BY month) AS prev_month_revenue,
    ROUND(
        (gross_revenue - LAG(gross_revenue) OVER (ORDER BY month)) 
        / LAG(gross_revenue) OVER (ORDER BY month) * 100, 2
    ) AS mom_growth_pct
FROM monthly
ORDER BY month;


-- Q4: Revenue by insurance type
-- Skills: CASE WHEN, aggregate, percentage calculation
SELECT
    p.insurance_type,
    COUNT(DISTINCT p.patientID) AS patient_count,
    COUNT(b.billingID) AS total_sessions,
    SUM(b.amount) AS gross_revenue,
    ROUND(AVG(b.amount), 2) AS avg_session_revenue,
    SUM(b.insurance_covered) AS total_insurance_paid,
    SUM(b.patient_copay) AS total_copay,
    ROUND(SUM(CASE WHEN b.payment_status = 'Denied' THEN b.amount ELSE 0 END) / SUM(b.amount) * 100, 2) AS denial_rate
FROM patient p
JOIN appointment a ON p.patientID = a.patientID
JOIN session_record sr ON a.appointmentID = sr.appointmentID
JOIN billing b ON sr.sessionID = b.sessionID
GROUP BY p.insurance_type
ORDER BY gross_revenue DESC;


-- ============================================================
-- PILLAR 2: PATIENT RETENTION & ENGAGEMENT
-- ============================================================

-- Q5: Patient churn analysis — patients who stopped coming back
-- Skills: CTE, DATEDIFF, CASE WHEN, window function
WITH patient_last_activity AS (
    SELECT
        p.patientID,
        p.name,
        p.insurance_type,
        p.referral_source,
        p.enrollment_date,
        MAX(a.date) AS last_appointment,
        COUNT(a.appointmentID) AS total_appointments,
        SUM(CASE WHEN a.status = 'Completed' THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN a.status IN ('Canceled', 'No-show') THEN 1 ELSE 0 END) AS missed
    FROM patient p
    JOIN appointment a ON p.patientID = a.patientID
    GROUP BY p.patientID, p.name, p.insurance_type, p.referral_source, p.enrollment_date
)
SELECT
    patientID,
    name,
    insurance_type,
    referral_source,
    enrollment_date,
    DATE(last_appointment) AS last_appointment,
    total_appointments,
    completed,
    missed,
    ROUND(missed / total_appointments * 100, 2) AS miss_rate,
    DATEDIFF('2025-06-30', last_appointment) AS days_since_last_visit,
    CASE
        WHEN DATEDIFF('2025-06-30', last_appointment) > 90 THEN 'Churned'
        WHEN DATEDIFF('2025-06-30', last_appointment) > 45 THEN 'At Risk'
        ELSE 'Active'
    END AS retention_status
FROM patient_last_activity
ORDER BY days_since_last_visit DESC;


-- Q6: Churn summary by insurance type and referral source
-- Skills: CTE, nested CTE, CASE WHEN
WITH patient_status AS (
    SELECT
        p.patientID,
        p.insurance_type,
        p.referral_source,
        MAX(a.date) AS last_appointment,
        CASE
            WHEN DATEDIFF('2025-06-30', MAX(a.date)) > 90 THEN 'Churned'
            WHEN DATEDIFF('2025-06-30', MAX(a.date)) > 45 THEN 'At Risk'
            ELSE 'Active'
        END AS retention_status
    FROM patient p
    JOIN appointment a ON p.patientID = a.patientID
    GROUP BY p.patientID, p.insurance_type, p.referral_source
)
SELECT
    insurance_type,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN retention_status = 'Active' THEN 1 ELSE 0 END) AS active,
    SUM(CASE WHEN retention_status = 'At Risk' THEN 1 ELSE 0 END) AS at_risk,
    SUM(CASE WHEN retention_status = 'Churned' THEN 1 ELSE 0 END) AS churned,
    ROUND(SUM(CASE WHEN retention_status = 'Churned' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS churn_rate
FROM patient_status
GROUP BY insurance_type
ORDER BY churn_rate DESC;


-- Q7: Cancellation rate by day of week, insurance, and frequency
-- Skills: CASE WHEN, multiple GROUP BY dimensions
SELECT
    DAYNAME(a.date) AS day_of_week,
    at_tbl.frequency,
    COUNT(a.appointmentID) AS total_appointments,
    SUM(CASE WHEN a.status = 'Completed' THEN 1 ELSE 0 END) AS completed,
    SUM(CASE WHEN a.status = 'Canceled' THEN 1 ELSE 0 END) AS canceled,
    SUM(CASE WHEN a.status = 'No-show' THEN 1 ELSE 0 END) AS no_shows,
    ROUND(SUM(CASE WHEN a.status IN ('Canceled', 'No-show') THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS miss_rate
FROM appointment a
JOIN assigned_to at_tbl ON a.patientID = at_tbl.patientID
GROUP BY DAYNAME(a.date), at_tbl.frequency
ORDER BY miss_rate DESC;


-- Q8: Patient progress trajectory — session-over-session score changes
-- Skills: Window Functions (LAG, ROW_NUMBER), CTE
WITH scored_sessions AS (
    SELECT
        a.patientID,
        p.name,
        sr.sessionID,
        sr.dateCompleted,
        sr.progress_score,
        ROW_NUMBER() OVER (PARTITION BY a.patientID ORDER BY sr.dateCompleted) AS session_number,
        LAG(sr.progress_score) OVER (PARTITION BY a.patientID ORDER BY sr.dateCompleted) AS prev_score
    FROM session_record sr
    JOIN appointment a ON sr.appointmentID = a.appointmentID
    JOIN patient p ON a.patientID = p.patientID
)
SELECT
    patientID,
    name,
    session_number,
    dateCompleted,
    progress_score,
    prev_score,
    CASE
        WHEN prev_score IS NULL THEN 'First Session'
        WHEN progress_score > prev_score THEN 'Improving'
        WHEN progress_score = prev_score THEN 'Stable'
        ELSE 'Declining'
    END AS trend
FROM scored_sessions
ORDER BY patientID, session_number;


-- Q9: Average progress score by month and specialty (improvement over time)
-- Skills: Window Function (AVG OVER), aggregate
SELECT
    DATE_FORMAT(sr.dateCompleted, '%Y-%m') AS month,
    t.specialty,
    COUNT(sr.sessionID) AS sessions,
    ROUND(AVG(sr.progress_score), 2) AS avg_progress_score,
    ROUND(AVG(sr.progress_score) - LAG(AVG(sr.progress_score)) 
        OVER (PARTITION BY t.specialty ORDER BY DATE_FORMAT(sr.dateCompleted, '%Y-%m')), 2) AS score_change
FROM session_record sr
JOIN appointment a ON sr.appointmentID = a.appointmentID
JOIN therapist t ON a.therapistID = t.therapistID
GROUP BY DATE_FORMAT(sr.dateCompleted, '%Y-%m'), t.specialty
ORDER BY t.specialty, month;


-- Q10: Patients at risk — declining progress + high cancellation
-- Skills: CTE, Window Function, HAVING, CASE WHEN
WITH patient_trends AS (
    SELECT
        a.patientID,
        p.name,
        p.insurance_type,
        t.name AS therapist_name,
        t.specialty,
        COUNT(sr.sessionID) AS total_sessions,
        ROUND(AVG(sr.progress_score), 2) AS avg_score,
        MAX(sr.progress_score) AS max_score,
        MIN(sr.progress_score) AS min_score,
        -- Get last 3 sessions average vs first 3 sessions average
        (SELECT ROUND(AVG(sr2.progress_score), 2)
         FROM session_record sr2
         JOIN appointment a2 ON sr2.appointmentID = a2.appointmentID
         WHERE a2.patientID = a.patientID
         ORDER BY sr2.dateCompleted DESC
         LIMIT 3) AS recent_avg_score
    FROM session_record sr
    JOIN appointment a ON sr.appointmentID = a.appointmentID
    JOIN patient p ON a.patientID = p.patientID
    JOIN therapist t ON a.therapistID = t.therapistID
    GROUP BY a.patientID, p.name, p.insurance_type, t.name, t.specialty
),
patient_cancellations AS (
    SELECT
        patientID,
        ROUND(SUM(CASE WHEN status IN ('Canceled', 'No-show') THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS miss_rate
    FROM appointment
    GROUP BY patientID
)
SELECT
    pt.patientID,
    pt.name,
    pt.insurance_type,
    pt.therapist_name,
    pt.specialty,
    pt.total_sessions,
    pt.avg_score,
    pt.recent_avg_score,
    pc.miss_rate,
    CASE
        WHEN pt.recent_avg_score < pt.avg_score AND pc.miss_rate > 25 THEN 'High Risk'
        WHEN pt.recent_avg_score < pt.avg_score OR pc.miss_rate > 25 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_level
FROM patient_trends pt
JOIN patient_cancellations pc ON pt.patientID = pc.patientID
ORDER BY 
    CASE
        WHEN pt.recent_avg_score < pt.avg_score AND pc.miss_rate > 25 THEN 1
        WHEN pt.recent_avg_score < pt.avg_score OR pc.miss_rate > 25 THEN 2
        ELSE 3
    END,
    pc.miss_rate DESC;


-- ============================================================
-- PILLAR 3: THERAPIST PERFORMANCE & UTILIZATION
-- ============================================================

-- Q11: Therapist performance scorecard
-- Skills: CTE, multiple aggregates, RANK window function
WITH therapist_metrics AS (
    SELECT
        t.therapistID,
        t.name,
        t.specialty,
        t.session_fee,
        COUNT(DISTINCT at_tbl.patientID) AS total_patients,
        COUNT(a.appointmentID) AS total_appointments,
        SUM(CASE WHEN a.status = 'Completed' THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN a.status = 'Canceled' THEN 1 ELSE 0 END) AS canceled,
        SUM(CASE WHEN a.status = 'No-show' THEN 1 ELSE 0 END) AS no_shows,
        ROUND(SUM(CASE WHEN a.status = 'Completed' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS completion_rate
    FROM therapist t
    JOIN assigned_to at_tbl ON t.therapistID = at_tbl.therapistID
    JOIN appointment a ON t.therapistID = a.therapistID
    GROUP BY t.therapistID, t.name, t.specialty, t.session_fee
)
SELECT
    tm.*,
    ROUND(completed * session_fee, 2) AS actual_revenue,
    ROUND((canceled + no_shows) * session_fee, 2) AS lost_revenue,
    RANK() OVER (ORDER BY completion_rate DESC) AS completion_rank,
    RANK() OVER (ORDER BY completed * session_fee DESC) AS revenue_rank,
    DENSE_RANK() OVER (ORDER BY total_patients DESC) AS patient_load_rank
FROM therapist_metrics tm
ORDER BY actual_revenue DESC;


-- Q12: Therapist utilization — sessions per week over time
-- Skills: Window Function, DATE arithmetic
SELECT
    t.name AS therapist_name,
    t.specialty,
    DATE_FORMAT(a.date, '%Y-%u') AS year_week,
    COUNT(CASE WHEN a.status = 'Completed' THEN 1 END) AS sessions_completed,
    COUNT(a.appointmentID) AS total_scheduled,
    ROUND(COUNT(CASE WHEN a.status = 'Completed' THEN 1 END) / COUNT(a.appointmentID) * 100, 2) AS weekly_utilization
FROM therapist t
JOIN appointment a ON t.therapistID = a.therapistID
GROUP BY t.name, t.specialty, DATE_FORMAT(a.date, '%Y-%u')
ORDER BY t.name, year_week;


-- Q13: Therapist effectiveness — average progress improvement per patient
-- Skills: CTE, Window Function (FIRST_VALUE, LAST_VALUE alternative with subqueries)
WITH patient_first_last AS (
    SELECT
        a.patientID,
        t.therapistID,
        t.name AS therapist_name,
        t.specialty,
        MIN(sr.dateCompleted) AS first_session_date,
        MAX(sr.dateCompleted) AS last_session_date,
        COUNT(sr.sessionID) AS session_count,
        (SELECT sr2.progress_score 
         FROM session_record sr2 
         JOIN appointment a2 ON sr2.appointmentID = a2.appointmentID 
         WHERE a2.patientID = a.patientID 
         ORDER BY sr2.dateCompleted ASC LIMIT 1) AS first_score,
        (SELECT sr2.progress_score 
         FROM session_record sr2 
         JOIN appointment a2 ON sr2.appointmentID = a2.appointmentID 
         WHERE a2.patientID = a.patientID 
         ORDER BY sr2.dateCompleted DESC LIMIT 1) AS last_score
    FROM session_record sr
    JOIN appointment a ON sr.appointmentID = a.appointmentID
    JOIN therapist t ON a.therapistID = t.therapistID
    GROUP BY a.patientID, t.therapistID, t.name, t.specialty
)
SELECT
    therapist_name,
    specialty,
    COUNT(patientID) AS patients_treated,
    ROUND(AVG(first_score), 2) AS avg_initial_score,
    ROUND(AVG(last_score), 2) AS avg_final_score,
    ROUND(AVG(last_score - first_score), 2) AS avg_improvement,
    ROUND(AVG(session_count), 1) AS avg_sessions_per_patient,
    RANK() OVER (ORDER BY AVG(last_score - first_score) DESC) AS effectiveness_rank
FROM patient_first_last
WHERE session_count >= 3  -- Only patients with 3+ sessions for meaningful comparison
GROUP BY therapist_name, specialty
ORDER BY avg_improvement DESC;


-- ============================================================
-- CLINICAL INSIGHTS
-- ============================================================

-- Q14: Most common mental health concerns with session counts
-- Skills: LEFT JOIN, aggregate, percentage
SELECT
    mhc.concernID,
    mhc.concernName,
    mhc.category,
    mhc.severity,
    COUNT(addr.sessionID) AS times_addressed,
    COUNT(DISTINCT a.patientID) AS unique_patients,
    ROUND(COUNT(addr.sessionID) / (SELECT COUNT(*) FROM session_record) * 100, 2) AS pct_of_sessions
FROM mental_health_concern mhc
LEFT JOIN addresses addr ON mhc.concernID = addr.concernID
LEFT JOIN session_record sr ON addr.sessionID = sr.sessionID
LEFT JOIN appointment a ON sr.appointmentID = a.appointmentID
GROUP BY mhc.concernID, mhc.concernName, mhc.category, mhc.severity
ORDER BY times_addressed DESC;


-- Q15: Concern co-occurrence matrix (self-join)
-- Skills: Self-join, aggregate
SELECT
    mhc1.concernName AS concern1,
    mhc2.concernName AS concern2,
    COUNT(*) AS co_occurrence_count
FROM addresses a1
JOIN addresses a2 ON a1.sessionID = a2.sessionID AND a1.concernID < a2.concernID
JOIN mental_health_concern mhc1 ON a1.concernID = mhc1.concernID
JOIN mental_health_concern mhc2 ON a2.concernID = mhc2.concernID
GROUP BY mhc1.concernName, mhc2.concernName
HAVING co_occurrence_count >= 3
ORDER BY co_occurrence_count DESC
LIMIT 20;


-- Q16: Temporal trends — monthly session volume with running total
-- Skills: Window Function (SUM OVER), running total
SELECT
    DATE_FORMAT(sr.dateCompleted, '%Y-%m') AS month,
    COUNT(sr.sessionID) AS monthly_sessions,
    COUNT(DISTINCT a.patientID) AS unique_patients,
    SUM(COUNT(sr.sessionID)) OVER (ORDER BY DATE_FORMAT(sr.dateCompleted, '%Y-%m')) AS cumulative_sessions,
    ROUND(AVG(sr.progress_score), 2) AS avg_progress_score
FROM session_record sr
JOIN appointment a ON sr.appointmentID = a.appointmentID
GROUP BY DATE_FORMAT(sr.dateCompleted, '%Y-%m')
ORDER BY month;


-- Q17: Severity distribution and average treatment duration
-- Skills: CTE, aggregate, CASE WHEN
WITH concern_treatment AS (
    SELECT
        mhc.severity,
        mhc.concernName,
        a.patientID,
        COUNT(DISTINCT sr.sessionID) AS sessions_per_patient,
        MIN(sr.dateCompleted) AS first_session,
        MAX(sr.dateCompleted) AS last_session,
        DATEDIFF(MAX(sr.dateCompleted), MIN(sr.dateCompleted)) AS treatment_days
    FROM mental_health_concern mhc
    JOIN addresses addr ON mhc.concernID = addr.concernID
    JOIN session_record sr ON addr.sessionID = sr.sessionID
    JOIN appointment a ON sr.appointmentID = a.appointmentID
    GROUP BY mhc.severity, mhc.concernName, a.patientID
)
SELECT
    severity,
    COUNT(DISTINCT concernName) AS concern_count,
    COUNT(DISTINCT patientID) AS total_patients,
    ROUND(AVG(sessions_per_patient), 2) AS avg_sessions_per_patient,
    ROUND(AVG(treatment_days), 0) AS avg_treatment_days,
    GROUP_CONCAT(DISTINCT concernName ORDER BY concernName SEPARATOR ', ') AS concerns
FROM concern_treatment
GROUP BY severity
ORDER BY FIELD(severity, 'Severe', 'Moderate', 'Mild');


-- Q18: Busiest appointment days with completion rates
-- Skills: CASE WHEN, aggregate, percentage
SELECT
    DAYNAME(a.date) AS day_of_week,
    COUNT(a.appointmentID) AS total_appointments,
    SUM(CASE WHEN a.status = 'Completed' THEN 1 ELSE 0 END) AS completed,
    SUM(CASE WHEN a.status = 'Canceled' THEN 1 ELSE 0 END) AS canceled,
    SUM(CASE WHEN a.status = 'No-show' THEN 1 ELSE 0 END) AS no_shows,
    ROUND(SUM(CASE WHEN a.status = 'Completed' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS completion_rate
FROM appointment a
GROUP BY DAYNAME(a.date)
ORDER BY total_appointments DESC;


-- Q19: Patient demographics segmentation analysis
-- Skills: CASE WHEN for age bucketing, multiple aggregates
SELECT
    CASE
        WHEN p.age BETWEEN 18 AND 25 THEN '18-25'
        WHEN p.age BETWEEN 26 AND 35 THEN '26-35'
        WHEN p.age BETWEEN 36 AND 45 THEN '36-45'
        WHEN p.age BETWEEN 46 AND 55 THEN '46-55'
        ELSE '56+'
    END AS age_group,
    p.gender,
    COUNT(DISTINCT p.patientID) AS patient_count,
    ROUND(AVG(sr.progress_score), 2) AS avg_progress,
    ROUND(SUM(CASE WHEN a.status IN ('Canceled', 'No-show') THEN 1 ELSE 0 END) / COUNT(a.appointmentID) * 100, 2) AS miss_rate
FROM patient p
JOIN appointment a ON p.patientID = a.patientID
LEFT JOIN session_record sr ON a.appointmentID = sr.appointmentID
GROUP BY age_group, p.gender
ORDER BY age_group, p.gender;


-- Q20: Sessions needed to reach score of 7+ (treatment milestone)
-- Skills: CTE, Window Function (ROW_NUMBER), MIN with condition
WITH scored_sessions AS (
    SELECT
        a.patientID,
        p.name,
        t.specialty,
        sr.progress_score,
        sr.dateCompleted,
        ROW_NUMBER() OVER (PARTITION BY a.patientID ORDER BY sr.dateCompleted) AS session_number
    FROM session_record sr
    JOIN appointment a ON sr.appointmentID = a.appointmentID
    JOIN patient p ON a.patientID = p.patientID
    JOIN therapist t ON a.therapistID = t.therapistID
),
first_milestone AS (
    SELECT
        patientID,
        name,
        specialty,
        MIN(session_number) AS sessions_to_reach_7
    FROM scored_sessions
    WHERE progress_score >= 7
    GROUP BY patientID, name, specialty
)
SELECT
    specialty,
    COUNT(patientID) AS patients_reaching_7,
    ROUND(AVG(sessions_to_reach_7), 1) AS avg_sessions_to_milestone,
    MIN(sessions_to_reach_7) AS fastest,
    MAX(sessions_to_reach_7) AS slowest
FROM first_milestone
GROUP BY specialty
ORDER BY avg_sessions_to_milestone;


-- ============================================================
-- EXPORT QUERIES FOR TABLEAU
-- ============================================================
-- These queries output flat tables suitable for Tableau data sources

-- Export 1: Full session-level detail for Tableau
SELECT
    p.patientID,
    p.name AS patient_name,
    p.age,
    p.gender,
    p.insurance_type,
    p.referral_source,
    p.enrollment_date,
    t.therapistID,
    t.name AS therapist_name,
    t.specialty,
    t.session_fee,
    at_tbl.frequency,
    a.appointmentID,
    a.date AS appointment_date,
    a.status AS appointment_status,
    sr.sessionID,
    sr.dateCompleted,
    sr.progress_score,
    b.amount AS billed_amount,
    b.insurance_covered,
    b.patient_copay,
    b.payment_status
FROM patient p
JOIN assigned_to at_tbl ON p.patientID = at_tbl.patientID
JOIN therapist t ON at_tbl.therapistID = t.therapistID
JOIN appointment a ON p.patientID = a.patientID AND t.therapistID = a.therapistID
LEFT JOIN session_record sr ON a.appointmentID = sr.appointmentID
LEFT JOIN billing b ON sr.sessionID = b.sessionID
ORDER BY p.patientID, a.date;

-- Export 2: Patient retention summary for Tableau
SELECT
    p.patientID,
    p.name,
    p.age,
    p.gender,
    p.insurance_type,
    p.referral_source,
    t.name AS therapist_name,
    t.specialty,
    at_tbl.frequency,
    COUNT(a.appointmentID) AS total_appointments,
    SUM(CASE WHEN a.status = 'Completed' THEN 1 ELSE 0 END) AS completed,
    SUM(CASE WHEN a.status IN ('Canceled', 'No-show') THEN 1 ELSE 0 END) AS missed,
    ROUND(SUM(CASE WHEN a.status IN ('Canceled', 'No-show') THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS miss_rate,
    MAX(a.date) AS last_appointment,
    DATEDIFF('2025-06-30', MAX(a.date)) AS days_inactive,
    CASE
        WHEN DATEDIFF('2025-06-30', MAX(a.date)) > 90 THEN 'Churned'
        WHEN DATEDIFF('2025-06-30', MAX(a.date)) > 45 THEN 'At Risk'
        ELSE 'Active'
    END AS retention_status,
    ROUND(AVG(sr.progress_score), 2) AS avg_progress_score
FROM patient p
JOIN assigned_to at_tbl ON p.patientID = at_tbl.patientID
JOIN therapist t ON at_tbl.therapistID = t.therapistID
JOIN appointment a ON p.patientID = a.patientID
LEFT JOIN session_record sr ON a.appointmentID = sr.appointmentID
GROUP BY p.patientID, p.name, p.age, p.gender, p.insurance_type, p.referral_source,
         t.name, t.specialty, at_tbl.frequency
ORDER BY miss_rate DESC;
