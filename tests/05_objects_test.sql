PROMPT Проверка состава и валидности объектов

DECLARE
    v_value NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO v_value
    FROM user_views
    WHERE view_name IN (
        'V_CURRENT_PLAYER', 'V_GAME_STATUS', 'V_TABLE',
        'V_HAND_MINE', 'V_HAND_PUBLIC', 'V_LOG',
        'V_REPLAY',
        'V_LEADERBOARD', 'V_DAILY', 'V_DAILY_RESULTS',
        'V_ERRORS',
        'V_GAME_CONSOLE', 'V_LOG_TEXT'
    );
    durak_test.assert_number('Созданы все 13 представлений', 13, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM user_objects
    WHERE object_name IN (
        'DURAK_RANDOM', 'DURAK_RULES', 'DURAK_ENGINE',
        'DURAK_API', 'DURAK_CONSOLE',
        'DURAK_MAINTENANCE', 'DURAK_TEST',
        'V_CURRENT_PLAYER', 'V_GAME_STATUS', 'V_TABLE',
        'V_HAND_MINE', 'V_HAND_PUBLIC', 'V_LOG',
        'V_REPLAY',
        'V_LEADERBOARD', 'V_DAILY', 'V_DAILY_RESULTS',
        'V_ERRORS',
        'V_GAME_CONSOLE', 'V_LOG_TEXT'
    )
      AND status <> 'VALID';
    durak_test.assert_number('Пакеты и представления валидны', 0, v_value);

    SELECT COUNT(*)
    INTO v_value
    FROM user_objects
    WHERE object_name IN (
        'DURAK_BOT', 'DURAK_TOURNAMENT_PKG', 'DURAK_BOT_DECISION',
        'DURAK_TOURNAMENT', 'DURAK_TOURNAMENT_PLAYER',
        'DURAK_TOURNAMENT_MATCH', 'V_ANALYTICS',
        'V_TOURNAMENT', 'V_TOURNAMENT_STANDINGS'
    );
    durak_test.assert_number(
        'Функции уровня «отлично» не установлены',
        0,
        v_value
    );

    SELECT COUNT(*)
    INTO v_value
    FROM user_scheduler_jobs
    WHERE job_name = 'DURAK_MAINTENANCE_JOB'
      AND enabled = 'TRUE';
    durak_test.assert_number('Фоновое задание таймеров включено', 1, v_value);
END;
/
