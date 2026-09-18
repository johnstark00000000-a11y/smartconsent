-- SmartConsent Database Schema
-- Run this in Supabase SQL Editor

-- ============================================================================
-- TABLES
-- ============================================================================

-- Patients table
CREATE TABLE IF NOT EXISTS patients (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  date_of_birth DATE,
  phone TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Procedures table
CREATE TABLE IF NOT EXISTS procedures (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  video_url TEXT,
  duration_minutes INT,
  risk_level TEXT CHECK (risk_level IN ('low', 'medium', 'high')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Consent Records table
CREATE TABLE IF NOT EXISTS consent_records (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  patient_id UUID REFERENCES patients(id) ON DELETE CASCADE NOT NULL,
  procedure_id UUID REFERENCES procedures(id),
  procedure_name TEXT NOT NULL,
  procedure_description TEXT,
  video_url TEXT,
  quiz_passed BOOLEAN DEFAULT FALSE,
  quiz_score NUMERIC(5, 2),
  signature_data_hash TEXT NOT NULL,
  signature_timestamp TIMESTAMP WITH TIME ZONE,
  ip_address TEXT,
  user_agent TEXT,
  document_hash TEXT NOT NULL, -- SHA-256
  encrypted_document TEXT, -- AES-256 encrypted consent
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'signed', 'completed')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Quiz Questions table
CREATE TABLE IF NOT EXISTS quiz_questions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  procedure_id UUID REFERENCES procedures(id) ON DELETE CASCADE NOT NULL,
  question_text TEXT NOT NULL,
  option_a TEXT NOT NULL,
  option_b TEXT NOT NULL,
  option_c TEXT NOT NULL,
  option_d TEXT NOT NULL,
  correct_answer TEXT CHECK (correct_answer IN ('a', 'b', 'c', 'd')),
  explanation TEXT,
  "order" INT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Audit Logs table (immutable)
CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  consent_record_id UUID REFERENCES consent_records(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ip_address TEXT NOT NULL,
  user_agent TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_patients_user_id ON patients(user_id);
CREATE INDEX idx_patients_email ON patients(email);
CREATE INDEX idx_consent_records_patient_id ON consent_records(patient_id);
CREATE INDEX idx_consent_records_procedure_id ON consent_records(procedure_id);
CREATE INDEX idx_consent_records_status ON consent_records(status);
CREATE INDEX idx_consent_records_created_at ON consent_records(created_at DESC);
CREATE INDEX idx_quiz_questions_procedure_id ON quiz_questions(procedure_id);
CREATE INDEX idx_audit_logs_consent_record_id ON audit_logs(consent_record_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE procedures ENABLE ROW LEVEL SECURITY;
ALTER TABLE consent_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE quiz_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Patients: Users can only see their own records
CREATE POLICY "Users can view own patient record"
  ON patients
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update own patient record"
  ON patients
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Procedures: All authenticated users can view
CREATE POLICY "Authenticated users can view procedures"
  ON procedures
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- Consent Records: Users can view their own consent records
CREATE POLICY "Users can view own consent records"
  ON consent_records
  FOR SELECT
  USING (
    patient_id IN (
      SELECT id FROM patients WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create consent records for themselves"
  ON consent_records
  FOR INSERT
  WITH CHECK (
    patient_id IN (
      SELECT id FROM patients WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update own consent records"
  ON consent_records
  FOR UPDATE
  USING (
    patient_id IN (
      SELECT id FROM patients WHERE user_id = auth.uid()
    )
  );

-- Quiz Questions: All authenticated users can view
CREATE POLICY "Authenticated users can view quiz questions"
  ON quiz_questions
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- Audit Logs: Users can view logs for their own consent records
CREATE POLICY "Users can view own audit logs"
  ON audit_logs
  FOR SELECT
  USING (
    consent_record_id IN (
      SELECT id FROM consent_records
      WHERE patient_id IN (
        SELECT id FROM patients WHERE user_id = auth.uid()
      )
    )
  );

-- ============================================================================
-- SAMPLE DATA (optional - remove in production)
-- ============================================================================

-- Insert sample procedure
INSERT INTO procedures (name, description, risk_level, duration_minutes)
VALUES (
  'Cardiac Catheterization',
  'A minimally invasive procedure to examine heart function and coronary arteries.',
  'high',
  45
) ON CONFLICT DO NOTHING;

-- Insert sample quiz questions
INSERT INTO quiz_questions (
  procedure_id,
  question_text,
  option_a,
  option_b,
  option_c,
  option_d,
  correct_answer,
  explanation,
  "order"
)
SELECT
  id,
  'What is the primary purpose of cardiac catheterization?',
  'To monitor blood pressure continuously',
  'To examine heart function and coronary arteries',
  'To administer anesthesia',
  'To measure oxygen levels',
  'b',
  'Cardiac catheterization is a diagnostic procedure that allows doctors to examine the heart''s chambers and coronary arteries.',
  1
FROM procedures
WHERE name = 'Cardiac Catheterization'
ON CONFLICT DO NOTHING;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to tables with updated_at
CREATE TRIGGER update_patients_updated_at
  BEFORE UPDATE ON patients
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_consent_records_updated_at
  BEFORE UPDATE ON consent_records
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
