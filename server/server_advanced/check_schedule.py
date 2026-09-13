"""проверка настроек интервала и сохранение следующего времени опроса"""

MAX_CHECK_INTERVAL = 1440

# старые регистрации без next_check_at сохраняют прежнее расписание
CHECK_IS_DUE_SQL = """(
    (next_check_at IS NULL AND last_check_at IS NULL)
    OR COALESCE(next_check_at,
        last_check_at + make_interval(mins => check_interval_minutes)) <= NOW()
)"""

# случайное число минут выбирается один раз при сохранении расписания
# clock_timestamp(), в отличие от NOW(), отсчитывает задержку от конца проверки,
# даже если соединение держало блокировку всё время запросов к eSchool
NEXT_CHECK_SQL = """clock_timestamp() + make_interval(mins =>
    check_interval_minutes + floor(random() * (
        COALESCE(check_interval_max_minutes, check_interval_minutes)
        - check_interval_minutes + 1
    ))::integer
)"""


def parse_check_interval(data, minimum):
    lower = data.get('checkIntervalMinutes')
    upper = data.get('checkIntervalMaxMinutes')
    if type(lower) is not int or not minimum <= lower <= MAX_CHECK_INTERVAL:
        raise ValueError(f'Интервал должен быть целым числом от {minimum} до {MAX_CHECK_INTERVAL} минут')
    if upper is not None:
        if type(upper) is not int or not lower < upper <= MAX_CHECK_INTERVAL:
            raise ValueError(f'Верхняя граница должна быть больше нижней и не больше {MAX_CHECK_INTERVAL} минут')
    return lower, upper


def schedule_next_check(cursor, registration_id):
    # читаем актуальные границы прямо в UPDATE: пользователь мог поменять их,
    # пока монитор выполнял сетевые запросы
    cursor.execute(f'''UPDATE cf3_registrations
        SET next_check_at = {NEXT_CHECK_SQL}
        WHERE id = %s''', (registration_id,))
