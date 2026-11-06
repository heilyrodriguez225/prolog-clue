/*  Sherlog: jugar una partida contra las IAs desde la terminal.

    Uso:

        swipl src/jugar.pl                    3 IAs: una media y dos fáciles
        swipl src/jugar.pl media media facil  las IAs que quieras, de 2 a 4

    Los niveles de IA son: azar, facil y media.

    Tú eres el jugador 1. Escribe el número de la opción que quieras.
    Con Ctrl-D abandonas la partida.
*/

:- use_module(library(main)).
:- use_module(sherlog).

:- initialization(main, main).

main(Argumentos) :-
    (   Argumentos == []
    ->  rivales_por_defecto(Rivales)
    ;   Rivales = Argumentos
    ),
    (   rivales_validos(Rivales)
    ->  jugar_en_consola(Rivales)
    ;   uso,
        halt(1)
    ).

uso :-
    niveles(Niveles),
    atomic_list_concat(Niveles, ', ', Texto),
    format(user_error, "Uso: swipl src/jugar.pl [nivel ...]~n", []),
    format(user_error, "  De 2 a 4 rivales, cada uno de estos niveles: ~w.~n", [Texto]),
    format(user_error, "  Sin argumentos juegas contra una IA media y dos fáciles.~n", []).
