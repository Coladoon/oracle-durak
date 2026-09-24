PROMPT Создание фонового задания таймеров DURAK_MAINTENANCE_JOB

BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'DURAK_MAINTENANCE_JOB',
        job_type        => 'STORED_PROCEDURE',
        job_action      => SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
            || '.DURAK_MAINTENANCE.RUN_ONCE',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=SECONDLY;INTERVAL=10',
        enabled         => TRUE,
        auto_drop       => FALSE,
        comments        => 'Авто-действия по таймеру и завершение простаивающих партий'
    );
END;
/

PROMPT Фоновое задание DURAK_MAINTENANCE_JOB создано
