/*  Sherlog: programa que arranca el servidor web.

        swipl src/servir.pl [puerto] [abierto]   (por defecto, el 8080)

    Por defecto solo se atiende a este ordenador. Con `abierto` también a
    la red local (cualquiera de ella podría abrir partidas).

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
    (   memberchk(abierto, Argv) -> Escuchar = [escuchar(todas)] ; Escuchar = [] ),
    poner_retardo(1.0),
    servidor_arrancar([port(Puerto)|Escuchar]),
    format("Sherlog en http://localhost:~w/  (Ctrl-C para parar)~n", [Puerto]),
    thread_get_message(_).
