/*  Demo: la IA (jugador 1) deduce la solución en una partida de
    21 cartas y 4 jugadores, a partir de lo que ve en cada turno.

    La partida está escrita a mano para que la demo dé siempre el mismo
    resultado y las observaciones sean coherentes con el reparto.

    Uso:  swipl src/demo.pl
*/

:- use_module(library(apply)).
:- use_module(library(aggregate)).
:- use_module(juego).
:- use_module(deduccion).
:- use_module(ia, [media_observar/3]).
:- use_module(explicacion).

:- initialization(main, main).

partida_demo(partida(sobre(senora_coral, cuerda, gimnasio),
                     [ 1-[chef_canela, daga, biblioteca, cocina, piscina],
                       2-[entrenador_cobalto, trofeo, sala_de_video, comedor, jardin],
                       3-[doctora_violeta, veneno, estudio, bodega],
                       4-[jardinero_verde, senorita_perla, revolver, tijeras]
                     ],
                     1, [], [])).

% Lo que la IA 1 ve en cada turno: descripción y eventos (los mismos que
% recibe un jugador en una partida, ver jugador.pl).
turno('Sugiero Entrenador Cobalto, Revólver, Gimnasio. El jugador 2 me enseña Entrenador Cobalto.',
      [ sugerencia(1, [entrenador_cobalto, revolver, gimnasio], [refuto(2)]),
        carta_vista(2, entrenador_cobalto) ]).
turno('El jugador 2 sugiere Señora Coral, Veneno, Jardín. El jugador 3 refuta (no veo la carta).',
      [ sugerencia(2, [senora_coral, veneno, jardin], [refuto(3)]) ]).
turno('El jugador 3 sugiere Doctora Violeta, Tijeras, Comedor. El jugador 4 refuta.',
      [ sugerencia(3, [doctora_violeta, tijeras, comedor], [refuto(4)]) ]).
turno('Sugiero Señora Coral, Cuerda, Sala de video. El jugador 2 me enseña Sala de video.',
      [ sugerencia(1, [senora_coral, cuerda, sala_de_video], [refuto(2)]),
        carta_vista(2, sala_de_video) ]).
turno('Sugiero Señora Coral, Cuerda, Biblioteca (la biblioteca es mía). Nadie puede refutar.',
      [ sugerencia(1, [senora_coral, cuerda, biblioteca], [no_pudo(2), no_pudo(3), no_pudo(4)]) ]).
turno('El jugador 3 sugiere Doctora Violeta, Veneno, Gimnasio. Ni el 4 ni el 2 pueden refutar.',
      [ sugerencia(3, [doctora_violeta, veneno, gimnasio], [no_pudo(4), no_pudo(1), no_pudo(2)]) ]).
turno('Sugiero Chef Canela, Daga, Gimnasio (las dos primeras son mías). Nadie puede refutar.',
      [ sugerencia(1, [chef_canela, daga, gimnasio], [no_pudo(2), no_pudo(3), no_pudo(4)]) ]).

% La IA 1 ve los eventos: los convierte en restricciones (K) y los apunta
% con su turno (Registro) para poder explicarse después.
%
% Ojo: nada de lambdas ni forall aquí: copiarían K y las restricciones
% se añadirían a la copia, no al conocimiento real.
ver_evento(K, Evento, R0, R) :-
    media_observar(1, Evento, K),
    registrar(1, Evento, R0, R).

main :-
    partida_demo(Partida),
    conocimiento_inicial(1, Partida, K),
    registro_inicial(1, Partida, R0),
    writeln('Soy la IA del jugador 1. Mis cartas: Chef Canela, Daga, Biblioteca, Cocina y Piscina.'),
    resumen(K),
    findall(T-Es, turno(T, Es), Turnos),
    foldl(jugar_turno(K), Turnos, 1-R0, _-R),
    acusar(K, R).

jugar_turno(K, Texto-Eventos, N-R0, N1-R) :-
    format("~nTurno ~w: ~w~n", [N, Texto]),
    foldl(ver_evento(K), Eventos, R0, R),
    resumen(K),
    N1 is N + 1.

resumen(K) :-
    deducir(K, Estados),
    findall(C, member(C-sobre, Estados), Sobre),
    aggregate_all(count, member(_-descartada, Estados), NDesc),
    aggregate_all(count, member(_-dudosa, Estados), NDud),
    maplist(nombre, Sobre, Nombres),
    format("  En el sobre: ~w · descartadas: ~w · dudosas: ~w~n", [Nombres, NDesc, NDud]).

acusar(K, R) :-
    (   solucion_segura(K, sobre(S0, A0, L0))
    ->  maplist(nombre, [S0, A0, L0], [S, A, L]),
        format("~nLa IA acusa: fue ~w, con ~w, en ~w.~n", [S, A, L]),
        writeln('\n¿Por qué? Esto es lo que la IA sabe y cuándo lo supo:\n'),
        explicar_acusacion(R, ctx(1, []), [S0, A0, L0], Texto),
        format("~s~n", [Texto])
    ;   writeln('\nTodavía no hay suficiente información para acusar.')
    ).
