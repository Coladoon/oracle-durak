PROMPT Проверка правил боя и лимитов

DECLARE
    v_value NUMBER;
BEGIN
    durak_test.assert_number(
        'Старшая карта той же масти бьёт младшую',
        1,
        durak_rules.can_beat('6C', '7C', 'S')
    );

    durak_test.assert_number(
        'Младшая карта той же масти не бьёт старшую',
        0,
        durak_rules.can_beat('7C', '6C', 'S')
    );

    durak_test.assert_number(
        'Козырь бьёт некозырь',
        1,
        durak_rules.can_beat('AH', '6S', 'S')
    );

    durak_test.assert_number(
        'Старший козырь бьёт младший',
        1,
        durak_rules.can_beat('6S', 'AS', 'S')
    );

    durak_test.assert_number(
        'Некозырь не бьёт козырь',
        0,
        durak_rules.can_beat('AS', 'AH', 'S')
    );

    durak_test.assert_number(
        'Другая некозырная масть не бьёт карту',
        0,
        durak_rules.can_beat('6C', 'AD', 'S')
    );

    durak_test.assert_number(
        'Равная карта не считается покрытием',
        0,
        durak_rules.can_beat_values(10, 'H', 10, 'H', 'S')
    );

    durak_test.assert_number(
        'Лимит стола для колоды 36',
        6,
        durak_rules.default_max_pairs(36)
    );

    durak_test.assert_number(
        'Лимит стола для колоды 52',
        8,
        durak_rules.default_max_pairs(52)
    );

    durak_test.assert_number(
        'Лимит атаки ограничен рукой защитника',
        3,
        durak_rules.effective_attack_limit(6, 3)
    );

    BEGIN
        v_value := durak_rules.can_beat_values(6, 'C', 7, 'C', NULL);
        durak_test.fail('Пустая козырная масть отклоняется', 'ошибка не возникла');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20601 THEN
                durak_test.pass('Пустая козырная масть отклоняется');
            ELSE
                durak_test.fail(
                    'Пустая козырная масть отклоняется',
                    'неожиданный код ' || SQLCODE
                );
            END IF;
    END;

    BEGIN
        v_value := durak_rules.default_max_pairs(40);
        durak_test.fail('Отклоняется размер колоды 40', 'ошибка не возникла');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20603 THEN
                durak_test.pass('Отклоняется размер колоды 40');
            ELSE
                durak_test.fail(
                    'Отклоняется размер колоды 40',
                    'неожиданный код ' || SQLCODE
                );
            END IF;
    END;

    BEGIN
        v_value := durak_rules.effective_attack_limit(6.5, 4);
        durak_test.fail('Лимит пар должен быть целым', 'ошибка не возникла');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20604 THEN
                durak_test.pass('Лимит пар должен быть целым');
            ELSE
                durak_test.fail(
                    'Лимит пар должен быть целым',
                    'неожиданный код ' || SQLCODE
                );
            END IF;
    END;
END;
/
