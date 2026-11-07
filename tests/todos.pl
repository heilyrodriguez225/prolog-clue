/*  Ejecuta todos los tests de Sherlog.

    Uso, desde la raíz del proyecto:

        swipl -q -g run_tests -t halt tests/todos.pl

    Termina con código 0 si todos pasan y con 1 si alguno falla.
*/

:- use_module(library(plunit)).

:- consult(test_juego).
:- consult(test_deduccion).
:- consult(test_consola).
:- consult(test_ia).
:- consult(test_jugador).
:- consult(test_turnos).
:- consult(test_sherlog).
:- consult(test_servidor).
