/*  Sherlog: 100 partidas completas solo entre IAs.

    No forma parte de tests/todos.pl porque tarda más (unos 20 segundos).
    Sirve para comprobar que el juego es estable: muchas partidas
    seguidas, con distintos números de jugadores y mezclas de IAs, y
    ninguna con un error ni con algo incoherente.

    Uso, desde la raíz del proyecto:

        swipl tests/partidas_largas.pl            semilla por defecto (2026)
        swipl tests/partidas_largas.pl 7          otra semilla

    Termina con código 0 si todas las partidas están bien y con 1 si no.
*/

:- use_module(library(main)).
:- use_module(library(lists)).
:- use_module(library(aggregate)).
:- use_module('../src/deduccion', [posibles_en_sobre/2]).
:- use_module('../src/jugador', [evento_publico/1]).
:- use_module('../src/turnos').

:- initialization(main, main).

% Las mezclas de IAs y cuántas partidas se juegan con cada una (100 en total).
configuraciones([ [media, facil, azar]-20,
                  [media, media, facil, azar]-20,
                  [media, facil, facil, azar, azar]-20,
                  [media, media, media, media]-20,
                  [facil, facil, facil]-20 ]).

semilla_por_defecto(2026).

main(Argumentos) :-
    semilla(Argumentos, Semilla),
    set_random(seed(Semilla)),
    configuraciones(Configuraciones),
    format("Sherlog: partidas largas entre IAs (semilla ~w)~n~n", [Semilla]),
    statistics(cputime, T0),
    maplist(jugar_configuracion, Configuraciones, Informes),
    statistics(cputime, T1),
    Segundos is T1 - T0,
    resumen(Informes, Segundos, Problemas),
    (   Problemas =:= 0
    ->  halt(0)
    ;   halt(1)
    ).

semilla([], S) :- !, semilla_por_defecto(S).
semilla([Texto|_], S) :-
    (   atom_number(Texto, N), integer(N)
    ->  S = N
    ;   format(user_error, "La semilla tiene que ser un número entero.~n", []),
        halt(1)
    ).

%   ---------------------------------------------------------------------
%   Jugar

% Juega las partidas de una mezcla y devuelve un informe
% informe(Tipos, Partidas, Ganadores, Eventos, Problemas, Segundos).
jugar_configuracion(Tipos-Cuantas, informe(Tipos, Cuantas, Ganadores, Eventos, Problemas, Segundos)) :-
    statistics(cputime, T0),
    numlist(1, Cuantas, Numeros),
    maplist(jugar_una(Tipos), Numeros, Resultados),
    statistics(cputime, T1),
    Segundos is T1 - T0,
    findall(G, member(partida(G, _, _), Resultados), Ganadores),
    findall(E, member(partida(_, E, _), Resultados), Eventos),
    findall(N-P, ( member(partida(_, _, Ps), Resultados), member(N-P, Ps) ), Problemas0),
    Problemas = Problemas0,
    informar_configuracion(Tipos, Cuantas, Ganadores, Eventos, Problemas, Segundos).

% Una partida: devuelve partida(Ganador, Eventos, [Numero-Problema, ...]).
% Que la partida lance un error, o simplemente falle, es un problema más.
jugar_una(Tipos, Numero, partida(Ganador, Eventos, Problemas)) :-
    (   catch(jugar_y_comprobar(Tipos, Ganador, Eventos, Problemas0),
              Error,
              ( Ganador = 0, Eventos = 0, Problemas0 = [error(Error)] ))
    ->  true
    ;   Ganador = 0, Eventos = 0, Problemas0 = [la_partida_fallo]
    ),
    findall(Numero-P, member(P, Problemas0), Problemas).

jugar_y_comprobar(Tipos, Ganador, Eventos, Problemas) :-
    iniciar_partida(Tipos, Partida, Jugadores),
    jugar(Partida, Jugadores, Resultado),
    Resultado = fin(Ganador, _, partida(_, _, _, _, Historial), _),
    length(Historial, Eventos),
    comprobar(Tipos, Resultado, Problemas).

%   ---------------------------------------------------------------------
%   Comprobaciones de una partida terminada

% Problemas es la lista de cosas incoherentes; vacía si la partida está bien.
comprobar(Tipos, fin(Ganador, Motivo, Partida, Jugadores), Problemas) :-
    Partida = partida(sobre(S, A, L), _, _, Eliminados, Historial),
    length(Tipos, N),
    findall(P, problema(Tipos, N, Ganador, Motivo, [S, A, L], Eliminados, Historial, Jugadores, P), Problemas).

problema(_, N, Ganador, _, _, _, _, _, ganador_fuera_de_rango(Ganador)) :-
    \+ ( integer(Ganador), between(1, N, Ganador) ).
problema(_, _, Ganador, _, _, Eliminados, _, _, ganador_eliminado(Ganador)) :-
    memberchk(Ganador, Eliminados).
problema(_, _, Ganador, acierta, Sobre, _, Historial, _, acierto_sin_acusacion_correcta) :-
    \+ ( last(Historial, acusacion(Ganador, Sobre, acierta)) ).
problema(_, N, _, ultimo, _, Eliminados, _, _, eliminados_que_no_cuadran) :-
    length(Eliminados, E),
    E =\= N - 1.
problema(Tipos, _, _, _, _, Eliminados, _, _, ia_eliminada(Id, Tipo)) :-
    member(Id, Eliminados),
    nth1(Id, Tipos, Tipo),
    memberchk(Tipo, [media, facil]).          % estas IAs solo acusan cuando están seguras
problema(_, _, _, _, _, Eliminados, Historial, _, eliminado_sin_acusacion_fallida(Id)) :-
    member(Id, Eliminados),
    \+ memberchk(acusacion(Id, _, falla), Historial).
problema(_, _, _, _, _, _, Historial, _, evento_no_publico(E)) :-
    member(E, Historial),
    \+ evento_publico(E).
problema(_, _, _, _, _, _, Historial, _, juega_dos_veces_seguidas(Id)) :-
    findall(Q, ( member(E, Historial), arg(1, E, Q) ), Quienes),
    append(_, [Id, Id|_], Quienes).
problema(_, _, _, _, _, _, Historial, _, juega_un_eliminado(Id)) :-
    juega_tras_caer(Historial, [], Id).
problema(_, _, _, _, Sobre, _, _, Jugadores, ia_media_descarta_el_sobre_real(Id)) :-
    member(jugador(Id, media, mente(K, _)), Jugadores),
    posibles_en_sobre(K, Posibles),
    \+ forall(member(C, Sobre), memberchk(C, Posibles)).
problema(_, _, _, _, Sobre, _, _, Jugadores, ia_facil_cree_vista_una_carta_del_sobre(Id)) :-
    member(jugador(Id, facil, vistas(Vistas)), Jugadores),
    member(C, Sobre),
    memberchk(C, Vistas).

% Quien juega no puede haber caído antes con una acusación fallida.
juega_tras_caer([E|Resto], Caidos, Id) :-
    arg(1, E, Quien),
    (   memberchk(Quien, Caidos)
    ->  Id = Quien
    ;   ( E = acusacion(_, _, falla) -> Caidos1 = [Quien|Caidos] ; Caidos1 = Caidos ),
        juega_tras_caer(Resto, Caidos1, Id)
    ).

%   ---------------------------------------------------------------------
%   Informes

informar_configuracion(Tipos, Cuantas, Ganadores, Eventos, Problemas, Segundos) :-
    length(Tipos, N),
    findall(Id-V, ( between(1, N, Id), aggregate_all(count, member(Id, Ganadores), V) ), Victorias),
    sum_list(Eventos, SE),
    Media is SE / Cuantas,
    length(Problemas, NP),
    format("~w (~w jugadores) · ~w partidas · ~1f eventos de media · victorias por puesto ~w · ~1f s~n",
           [Tipos, N, Cuantas, Media, Victorias, Segundos]),
    (   NP =:= 0
    ->  true
    ;   format("  ¡~w problemas en esta mezcla!~n", [NP])
    ).

resumen(Informes, Segundos, NProblemas) :-
    format("~n"),
    % Victorias de cada tipo de IA, sobre todas las partidas.
    findall(Tipo-1,
            ( member(informe(Tipos, _, Ganadores, _, _, _), Informes),
              member(G, Ganadores),
              nth1(G, Tipos, Tipo) ),
            Cada),
    findall(Tipo-Total, aggregate(sum(V), member(Tipo-V, Cada), Total), PorTipo0),
    msort(PorTipo0, PorTipo),
    aggregate_all(sum(C), member(informe(_, C, _, _, _, _), Informes), Partidas),
    format("Victorias por tipo de IA, en las ~w partidas: ~w~n", [Partidas, PorTipo]),
    % Las partidas donde compiten niveles distintos.
    victorias_en_mezclas(Informes, Media, Facil, Azar),
    format("En las partidas con IAs de niveles distintos (media/facil/azar): media ~w · facil ~w · azar ~w~n",
           [Media, Facil, Azar]),
    findall(P, ( member(informe(_, _, _, _, Ps, _), Informes), member(P, Ps) ), Todos),
    length(Todos, NProblemas0),
    format("Tiempo total: ~1f s~n", [Segundos]),
    (   NProblemas0 =:= 0
    ->  format("~nTodas las partidas terminaron sin errores ni incoherencias.~n")
    ;   format("~n¡Hay ~w problemas!~n", [NProblemas0]),
        forall(member(Numero-Problema, Todos),
               format("  partida ~w de su mezcla: ~q~n", [Numero, Problema]))
    ),
    comprobar_niveles(Media, Facil, Azar, Fallos),
    forall(member(F, Fallos), format("~w~n", [F])),
    length(Fallos, NFallos),
    NProblemas is NProblemas0 + NFallos.

% Cuántas partidas gana cada nivel donde hay niveles distintos.
victorias_en_mezclas(Informes, Media, Facil, Azar) :-
    findall(Tipo,
            ( member(informe(Tipos, _, Ganadores, _, _, _), Informes),
              sort(Tipos, [_, _|_]),                 % más de un nivel distinto
              member(G, Ganadores),
              nth1(G, Tipos, Tipo) ),
            Ganadas),
    aggregate_all(count, member(media, Ganadas), Media),
    aggregate_all(count, member(facil, Ganadas), Facil),
    aggregate_all(count, member(azar, Ganadas), Azar).

% La IA media debe ganar más que la fácil y que la de azar donde compiten.
comprobar_niveles(Media, Facil, Azar, Fallos) :-
    findall(Mensaje,
            (   Media =< Facil, Mensaje = "¡La IA media no gana más partidas que la fácil!"
            ;   Media =< Azar,  Mensaje = "¡La IA media no gana más partidas que la de azar!" ),
            Fallos).
