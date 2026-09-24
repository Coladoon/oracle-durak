SET DEFINE ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

PROMPT Полная переустановка проекта «Дурак».
PROMPT ВНИМАНИЕ: существующие игровые данные будут удалены.

@@sql/00_drop.sql
@@install.sql
