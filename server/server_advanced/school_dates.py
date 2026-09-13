"""даты дневника считаем по московской полуночи, часы базы и очереди оставляем в utc"""
from datetime import datetime, timedelta, timezone

SCHOOL_TIMEZONE = timezone(timedelta(hours=3), name='MSK')


def school_datetime(milliseconds):
    return datetime.fromtimestamp(float(milliseconds) / 1000, SCHOOL_TIMEZONE)


def school_date(milliseconds):
    return school_datetime(milliseconds).date().isoformat()
