/*  Sherlog: programa que arranca el servidor web.

        swipl src/servir.pl [puerto]        (por defecto, el 8080)

    La lógica está en servidor.pl; este archivo solo lo pone en marcha. Va
    aparte porque `initialization(..., main)` se ejecuta al cargar el
    archivo, y los tests tienen que poder cargar servidor.pl sin arrancar nada.
*/

:- use_module(servidor).
:- use_module(puente, [poner_retardo/1]).

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Argv),
    (   Argv = [Texto|_],
        atom_number(Texto, Puerto),
        integer(Puerto)
    ->  true
    ;   Puerto = 8080
    ),
    poner_retardo(1.0),
    servidor_arrancar([port(Puerto)]),
    format("Sherlog en http://localhost:~w/  (Ctrl-C para parar)~n", [Puerto]),
    thread_get_message(_).
