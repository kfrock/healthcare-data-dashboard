USE healthcare_practice;

-- =====================================================
-- DATA QUALITY ANALYSIS
-- =====================================================

-- Duplicate patients with identical information
SELECT 
    first_name,
    last_name,
    birth_date,
    gender,
    email,
    phone,
    COUNT(*) AS duplicate_count
FROM patient_registry
GROUP BY 
    first_name,
    last_name,
    birth_date,
    gender,
    email,
    phone
HAVING COUNT(*) > 1;


-- Patients with same name + DOB but conflicting contact info
WITH duplicates AS (
    SELECT
        first_name,
        last_name,
        birth_date,
        COUNT(*) AS duplicate_count,
        COUNT(DISTINCT COALESCE(email, 'NO_EMAIL')) AS distinct_emails,
        COUNT(DISTINCT COALESCE(phone, 'NO_PHONE')) AS distinct_phones
    FROM patient_registry
    GROUP BY first_name, last_name, birth_date
    HAVING COUNT(*) > 1
       AND (
            COUNT(DISTINCT email) > 1
            OR COUNT(DISTINCT phone) > 1
       )
)
SELECT
    d.first_name,
    d.last_name,
    d.birth_date,
    d.duplicate_count,
    p.email,
    p.phone,
    p.source_system
FROM patient_registry p
JOIN duplicates d
    ON p.first_name = d.first_name
   AND p.last_name = d.last_name
   AND p.birth_date = d.birth_date;


-- Patients appearing across multiple source systems
WITH sc AS (
    SELECT
        first_name,
        last_name,
        birth_date,
        COUNT(DISTINCT source_system) AS system_count
    FROM patient_registry
    GROUP BY first_name, last_name, birth_date
    HAVING COUNT(DISTINCT source_system) > 1
)
SELECT p.*
FROM patient_registry p
JOIN sc
    ON p.first_name = sc.first_name
   AND p.last_name = sc.last_name
   AND p.birth_date = sc.birth_date;


-- =====================================================
-- FINANCIAL / REVENUE ANALYSIS
-- =====================================================

-- Visit financial breakdown
SELECT
    visit_id,
    patient_id,
    total_charge,
    COALESCE(insurance_paid, 0) AS insurance_payment,
    COALESCE(patient_paid, 0) AS patient_payment,
    total_charge 
        - COALESCE(insurance_paid, 0)
        - COALESCE(patient_paid, 0) AS balance_due
FROM visits;


-- High vs low charge visits by department
SELECT
    department,
    SUM(CASE WHEN total_charge >= 700 THEN 1 ELSE 0 END) AS high_charge_visits,
    SUM(CASE WHEN total_charge < 700 THEN 1 ELSE 0 END) AS low_charge_visits
FROM visits
GROUP BY department;


-- Revenue ranking by clinic and department
WITH revenue_by_dept AS (
    SELECT
        c.clinic_name,
        v.department,
        SUM(v.total_charge) AS department_revenue
    FROM visits v
    LEFT JOIN providers p ON v.provider_id = p.provider_id
    LEFT JOIN clinics c ON c.clinic_id = p.clinic_id
    GROUP BY c.clinic_name, v.department
),
ranked_revenue AS (
    SELECT *,
           RANK() OVER (PARTITION BY clinic_name ORDER BY department_revenue DESC) AS revenue_rank
    FROM revenue_by_dept
)
SELECT *
FROM ranked_revenue
WHERE revenue_rank <= 2;


-- =====================================================
-- PATIENT RISK ANALYSIS (used in dashboard)
-- =====================================================

-- Patients with abnormal lab results
SELECT p.patient_id, p.first_name, p.last_name
FROM patients p
WHERE EXISTS (
    SELECT 1
    FROM lab_results l
    WHERE l.patient_id = p.patient_id
      AND l.abnormal_flag = 'Y'
);


-- Patients with ER visits
SELECT p.*
FROM patients p
WHERE EXISTS (
    SELECT 1
    FROM visits v
    WHERE v.patient_id = p.patient_id
      AND v.department = 'Emergency'
);


-- Patients with active medications
SELECT p.patient_id, p.first_name, p.last_name
FROM patients p
WHERE EXISTS (
    SELECT 1
    FROM medications m
    WHERE m.patient_id = p.patient_id
      AND m.end_date IS NULL
);


-- Overlapping medications (potential risk indicator)
SELECT
    m1.patient_id,
    m1.medication_name AS med1,
    m2.medication_name AS med2
FROM medications m1
JOIN medications m2
    ON m1.patient_id = m2.patient_id
   AND m1.rx_id < m2.rx_id
   AND m1.start_date <= COALESCE(m2.end_date, CURRENT_DATE)
   AND m2.start_date <= COALESCE(m1.end_date, CURRENT_DATE);


-- =====================================================
-- OPERATIONS / UTILIZATION ANALYSIS
-- =====================================================

-- Most recent visit per patient
WITH mrv AS (
    SELECT
        patient_id,
        visit_id,
        visit_date,
        department,
        ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY visit_date DESC) AS rn
    FROM visits
)
SELECT *
FROM mrv
WHERE rn = 1;


-- Rank visits by charge within department
SELECT
    visit_id,
    department,
    total_charge,
    RANK() OVER (PARTITION BY department ORDER BY total_charge DESC) AS rank_num
FROM visits;


-- Top 2 visits per department
WITH dc AS (
    SELECT
        department,
        visit_id,
        total_charge,
        ROW_NUMBER() OVER (PARTITION BY department ORDER BY total_charge DESC) AS rn
    FROM visits
)
SELECT *
FROM dc
WHERE rn <= 2;


-- Monthly visit volume
SELECT
    DATE_FORMAT(visit_date, '%Y-%m') AS month,
    COUNT(*) AS total_visits
FROM visits
GROUP BY month
ORDER BY month;


-- Monthly revenue
SELECT
    DATE_FORMAT(visit_date, '%Y-%m') AS month,
    SUM(total_charge) AS revenue 
FROM visits
GROUP BY month
ORDER BY month;