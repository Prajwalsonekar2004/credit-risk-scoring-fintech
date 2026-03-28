DROP TABLE IF EXISTS application_raw;

CREATE TABLE application_raw AS
SELECT
    sk_id_curr,
    target,
    amt_income_total,
    amt_credit,
    amt_annuity,
    name_income_type,
    name_education_type,
    name_family_status,
	name_housing_type,
    days_birth,
    days_employed,
    ext_source_1,
    ext_source_2,
    ext_source_3
FROM application_raw_full;

SELECT * FROM application_raw_full LIMIT 20;
SELECT COUNT(*) FROM application_raw_full

SELECT * FROM application_raw LIMIT 20;
SELECT COUNT(*) FROM application_raw;

CREATE TABLE application_clean AS
SELECT sk_id_curr, target, ABS(days_birth) / 365 AS age,
CASE WHEN days_employed > 0 THEN NULL ELSE ABS(days_employed) END AS employment_days,
COALESCE(amt_income_total, 0) AS income, amt_credit AS loan_amount, amt_annuity AS emi,
COALESCE(ext_source_1, 0.5) AS ext_1,
COALESCE(ext_source_2, 0.5) AS ext_2,
COALESCE(ext_source_3, 0.5) AS ext_3, name_income_type, name_education_type, name_family_status, name_housing_type
FROM application_raw;

SELECT * FROM application_clean LIMIT 20;
SELECT COUNT(*) FROM application_clean;

CREATE TABLE loan_features AS
SELECT *, 
-- Debt-to-Income Ratio (IMP)
loan_amount / NULLIF(income, 0) AS debt_to_income,
-- EMI
emi / NULLIF(income, 0) AS emi_to_income,
 -- Average risk score
(ext_1 + ext_2 + ext_3) / 3 AS avg_risk_score,
-- Income stability proxy
employment_days / 365 AS years_employed
FROM application_clean;

SELECT * FROM loan_features LIMIT 20;
-- 1.Default Rate
SELECT COUNT(*) AS total_loans, SUM(target) AS total_defaults, 
ROUND(SUM(target::DECIMAL) / NULLIF(COUNT(*), 0) * 100, 2) AS defaults_percent
FROM loan_features;

-- 2.Default by Income Level
SELECT CASE
WHEN income < 100000 THEN 'Low Income'
WHEN income < 300000 THEN 'Medium Income'
ELSE 'High Income' END AS income_level,
COUNT(*) AS total_loans, SUM(target) AS total_defualts,
ROUND(SUM(target)::DECIMAL / COUNT(*) * 100, 2) AS defualt_rate_by_income
FROM loan_features
GROUP BY income_level
ORDER BY defualt_rate_by_income DESC;

-- 3.Default by Credit Risk Score
SELECT CASE
WHEN avg_risk_score >= 0.7 THEN 'Low Risk'
WHEN avg_risk_score >= 0.4 THEN 'Medium Risk' 
ELSE 'High Risk' END AS risk_bucket,
COUNT(*) total_loans, SUM(target) AS total_defaults,
ROUND(SUM(target::DECIMAL) / NULLIF(COUNT(*), 0) * 100, 2) AS defualt_rate_pct
FROM loan_features
GROUP BY 1
ORDER BY defualt_rate_pct DESC;

-- 4.High Risk Segment (Business Insight)
SELECT COUNT(*) AS total_customers, SUM(target) AS total_faults,
ROUND(SUM(target::DECIMAL) / NULLIF(COUNT(*), 0) * 100, 2) AS default_pct
FROM loan_features
WHERE debt_to_income > 0.6;

SELECT * FROM loan_features LIMIT 20;
SELECT * FROM loan_predictions LIMIT 20;
SELECT COUNT(*) FROM loan_predictions;

-- Final Scoring.
DROP TABLE final_scoring;

CREATE TABLE final_scoring AS
WITH percentiles AS (
SELECT 
PERCENTILE_CONT(0.80) WITHIN GROUP (ORDER BY risk_probability) AS p80,
PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY risk_probability) AS p50
FROM loan_predictions
)

SELECT f.*, p.risk_probability,
CASE 
WHEN p.risk_probability >= pct.p80 THEN 'High Risk'
WHEN p.risk_probability >= pct.p50 THEN 'Medium Risk'
ELSE 'Low Risk' END AS risk_category
FROM loan_features f
JOIN loan_predictions p ON f.sk_id_curr = p.sk_id_curr
CROSS JOIN percentiles pct;

SELECT * FROM final_scoring LIMIT 20;
SELECT COUNT(*) FROM final_scoring;

-- KPI's..
-- total apl according to the risk category?
SELECT risk_category, COUNT(*)
FROM final_scoring
GROUP BY risk_category;

-- avg default rate by risk category?
SELECT risk_category, ROUND(AVG(target),2) AS defualt_rate
FROM final_scoring
GROUP BY risk_category
ORDER BY defualt_rate DESC;

-- defualt rate
SELECT ROUND(AVG(target),2) AS defualt_rate
FROM final_scoring;

-- avg loan amount
SELECT ROUND(AVG(loan_amount::NUMERIC),2) AS avg_loan_amount
FROM final_scoring;

-- avg income
SELECT ROUND(AVG(income::NUMERIC),2) AS avg_income
FROM final_scoring;

-- Loans by Income Group
SELECT CASE
WHEN income < 100000 THEN 'Low Income'
WHEN income < 300000 THEN 'Medium Income'
ELSE 'High Income' END AS income_group, COUNT(*) AS total_loans
FROM final_scoring
GROUP BY income_group
ORDER BY total_loans DESC;

-- loans by risk category
SELECT risk_category, COUNT(*) AS total_loans
FROM final_scoring
GROUP BY risk_category
ORDER BY total_loans DESC;

SELECT * FROM final_scoring LIMIT 20;
-- intesrest strategy
SELECT CASE
WHEN risk_category = 'Low Risk' THEN 'Standard Interest'
WHEN risk_category = 'Medium Risk' THEN 'High Interest'
ELSE 'Not Eligible' END AS interest_strategy,
COUNT(*) AS loan_status
FROM final_scoring
GROUP BY interest_strategy
ORDER BY loan_status DESC;