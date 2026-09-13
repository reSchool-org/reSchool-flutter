-- не всякую домашку можно оценить: "доделать классную работу" или "доделать листочек"
-- без вложения это отсылка к тому, чего у нас нет. такое честнее пометить,
-- чем выдумывать минуты, и ждать, пока кто нибудь приложит фото листочка

ALTER TABLE homework_analysis
    ADD COLUMN IF NOT EXISTS estimable BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE homework_analysis
    ADD COLUMN IF NOT EXISTS unestimable_reason TEXT;

-- что именно ушло в модель: вложения учителя, свои файлы, вырезки из учебника
ALTER TABLE homework_analysis
    ADD COLUMN IF NOT EXISTS sources JSONB;

-- вложения учителя надо утащить, пока жива сессия eSchool,
-- поэтому их адреса кладём в разбор сразу при постановке в очередь
ALTER TABLE homework_analysis
    ADD COLUMN IF NOT EXISTS attachments JSONB;

-- своё дз оценивается с оглядкой на учительское за тот же день,
-- по этому индексу оно и ищется
CREATE INDEX IF NOT EXISTS idx_homework_analysis_day_subject
    ON homework_analysis (grade_class, lesson_date, subject, source);
