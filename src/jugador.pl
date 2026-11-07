/*  Sherlog: los jugadores y su memoria privada.

    Un jugador es un término

        jugador(Id, Tipo, Memoria)

    - Id es el número de jugador (1 es el humano).
    - Tipo es azar, humano, facil, media o dificil.
    - Memoria es lo que ese jugador sabe y los demás no. Su forma
      depende del tipo:

          azar, humano    []
          web             web(Id, Asistente)   la partida y su asistente,
                                               o none si no tiene
          facil           vistas(Cartas)   las cartas que ha visto
          media, dificil  mente(K, Mostradas)
                            K          el conocimiento de deduccion.pl,
                                       con sus restricciones CLP(FD)
                            Mostradas  las cartas que ha enseñado y a quién

    La memoria no se guarda con assert: el bucle de la partida lleva la
    lista de jugadores de turno en turno y cada operación devuelve el
    jugador con su memoria actualizada. Ver PLAN.md §3.
*/

:- module(jugador,
          [ tipo_de_jugador/1,
            nuevo_jugador/4,
            jugadores_iniciales/3,
            con_memoria/3,
            vista_de/3,
            elegir_accion/4,
            elegir_carta_a_mostrar/5,
            observar/3,
            evento_publico/1,
            evento_privado/1,
            observar_todos/3,
            observar_a/4
          ]).

:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module(deduccion).
:- use_module(ia).
:- use_module(consola).
:- use_module(puente).
:- use_module(juego, [carta/2]).

%!  tipo_de_jugador(?Tipo) is nondet.
%
%   Los tipos de jugador que existen.

tipo_de_jugador(humano).
tipo_de_jugador(facil).
tipo_de_jugador(media).
tipo_de_jugador(dificil).
tipo_de_jugador(azar).
tipo_de_jugador(web).

%!  nuevo_jugador(+Id, +Tipo, +Partida, -Jugador) is det.
%
%   Jugador es el jugador Id de la Partida, con la memoria con la que
%   empieza: solo lo que puede saber al principio (su propia mano).

nuevo_jugador(Id, Tipo, Partida, jugador(Id, Tipo, Memoria)) :-
    must_be(oneof([humano, facil, media, dificil, azar, web]), Tipo),
    memoria_inicial(Tipo, Id, Partida, Memoria).

memoria_inicial(humano, _, _, []).
memoria_inicial(azar, _, _, []).
% El jugador web recibe su memoria de verdad al crear la partida (servidor.pl).
memoria_inicial(web, _, _, web(sin_partida, none)).
memoria_inicial(facil, Id, Partida, vistas(Mano)) :-
    mano_de(Id, Partida, Mano).
memoria_inicial(media, Id, Partida, mente(K, [])) :-
    conocimiento_inicial(Id, Partida, K).
memoria_inicial(dificil, Id, Partida, mente(K, [])) :-
    conocimiento_inicial(Id, Partida, K).

mano_de(Id, partida(_, Manos, _, _, _), Mano) :-
    memberchk(Id-Mano, Manos).

%!  jugadores_iniciales(+Partida, +Tipos, -Jugadores) is det.
%
%   Jugadores es la lista de jugadores de la Partida, en orden de
%   turno. Tipos da el tipo de cada uno: [humano, media, facil, media].

jugadores_iniciales(Partida, Tipos, Jugadores) :-
    Partida = partida(_, Manos, _, _, _),
    length(Manos, N),
    length(Tipos, NTipos),
    (   N =:= NTipos
    ->  true
    ;   domain_error(un_tipo_por_jugador(N), Tipos)
    ),
    numlist(1, N, Ids),
    maplist(nuevo_jugador_de(Partida), Ids, Tipos, Jugadores).

nuevo_jugador_de(Partida, Id, Tipo, Jugador) :-
    nuevo_jugador(Id, Tipo, Partida, Jugador).

%!  con_memoria(+Jugador, +Memoria, -Jugador1) is det.
%
%   Jugador1 es el mismo jugador con otra memoria.

con_memoria(jugador(Id, Tipo, _), Memoria, jugador(Id, Tipo, Memoria)).

%   ---------------------------------------------------------------------
%   El protocolo
%
%   El bucle de la partida solo habla con los jugadores mediante las tres
%   operaciones de abajo, sin saber de qué tipo es cada uno. Cada
%   operación devuelve el jugador con su memoria actualizada.
%
%   Un jugador NUNCA recibe la partida entera (tendría el sobre y las
%   manos de los demás), solo su vista.

%!  vista_de(+Id, +Partida, -Vista) is det.
%
%   Vista = vista(Mano, Eliminados, Historial) es todo lo que el jugador
%   Id puede ver de la Partida: su mano, quién está eliminado y el
%   historial público (ver observar/3).

vista_de(Id, partida(_, Manos, _, Eliminados, Historial),
         vista(Mano, Eliminados, Historial)) :-
    memberchk(Id-Mano, Manos).

%!  elegir_accion(+Jugador, +Vista, -Accion, -Jugador1) is det.
%
%   Le toca a Jugador. Accion es sugerir(S, A, L) o acusar(S, A, L), con
%   un sospechoso, un arma y un lugar.

elegir_accion(Jugador, Vista, Accion, Jugador1) :-
    (   Vista = vista(_, _, _)
    ->  true
    ;   type_error(vista, Vista)       % p. ej. si alguien le pasa la partida
    ),
    Jugador = jugador(_, Tipo, _),
    elige_accion(Tipo, Jugador, Vista, Accion, Jugador1).

%!  elegir_carta_a_mostrar(+Jugador, +Sugerencia, +Candidatas, -Carta, -Jugador1) is det.
%
%   Jugador tiene que refutar la Sugerencia = sugerencia(Quien, [S, A, L]).
%   Candidatas son las cartas de la sugerencia que tiene (al menos una).
%   Carta es la que enseña, una de las Candidatas.

elegir_carta_a_mostrar(Jugador, Sugerencia, Candidatas, Carta, Jugador1) :-
    Jugador = jugador(_, Tipo, _),
    elige_carta(Tipo, Jugador, Sugerencia, Candidatas, Carta, Jugador1).

%!  observar(+Jugador, +Evento, -Jugador1) is det.
%
%   Pasó algo que Jugador puede ver. Jugador1 es el jugador con la
%   memoria actualizada. Los eventos se definen más abajo.

observar(Jugador, Evento, Jugador1) :-
    Jugador = jugador(_, Tipo, _),
    observa(Tipo, Jugador, Evento, Jugador1).

%   Un predicado por operación, con una cláusula por tipo de jugador
%   (Prolog elige la cláusula por el primer argumento).
%
%   Cada tipo de jugador:
%
%       azar      juega al azar y no aprende nada: es el nivel más bajo,
%                 la referencia con la que comparar a todos los demás
%       humano    pregunta por la terminal y cuenta lo que ocurre (consola.pl)
%       web       lo mismo, pero por una cola y una foto compartida con el
%                 servidor HTTP, no por la terminal (puente.pl)
%       facil     recuerda las cartas que le enseñan; sugiere las que
%                 no ha visto y acusa cuando solo le queda una de
%                 cada tipo (ia.pl)
%       media     convierte en restricciones todo lo que ve y deduce qué
%                 puede estar en el sobre; acusa solo cuando es seguro; y al
%                 refutar procura revelar lo menos posible (ia.pl)
%       dificil   POR AHORA juega al azar; además elegirá la mejor
%                 sugerencia                                          (#21)

elige_accion(azar,    J, _, Accion, J) :- accion_al_azar(Accion).
elige_accion(web,     J, Vista, Accion, J) :-
    J = jugador(Yo, web, web(Id, Asistente)),
    web_preguntar_accion(Id, Yo, Asistente, Vista, Accion).
elige_accion(humano,  J, Vista, Accion, J) :-
    J = jugador(Id, humano, _),
    preguntar_accion(Id, Vista, Accion).
elige_accion(facil,   J, _, Accion, J) :-
    J = jugador(_, facil, vistas(Vistas)),
    facil_accion(Vistas, Accion).
elige_accion(media,   J, _, Accion, J) :-
    J = jugador(_, media, mente(K, _)),
    media_accion(K, Accion).
elige_accion(dificil, J, _, Accion, J) :- accion_al_azar(Accion).

elige_carta(azar,    J, _, Candidatas, Carta, J) :- random_member(Carta, Candidatas).
elige_carta(web,     J, Sugerencia, Candidatas, Carta, J) :-
    J = jugador(_, web, web(Id, _)),
    web_preguntar_carta(Id, Sugerencia, Candidatas, Carta).
elige_carta(humano,  J, Sugerencia, Candidatas, Carta, J) :-
    preguntar_carta(Sugerencia, Candidatas, Carta).
elige_carta(facil,   J, _, Candidatas, Carta, J) :- random_member(Carta, Candidatas).
elige_carta(media, jugador(Id, media, mente(K, Mostradas)), sugerencia(Quien, _),
            Candidatas, Carta, jugador(Id, media, mente(K, Mostradas1))) :-
    media_carta_a_mostrar(Mostradas, Quien, Candidatas, Carta, Mostradas1).
elige_carta(dificil, J, _, Candidatas, Carta, J) :- random_member(Carta, Candidatas).

observa(azar,    J, _, J).
observa(web, J, Evento, J) :-
    J = jugador(Yo, web, web(Id, Asistente)),
    web_observar(Id, Yo, Asistente, Evento).
observa(humano, J, Evento, J) :-
    J = jugador(Id, humano, _),
    mostrar_evento(Id, Evento).
observa(facil, jugador(Id, facil, vistas(Vistas)), Evento, jugador(Id, facil, vistas(Vistas1))) :-
    facil_recordar(Evento, Vistas, Vistas1).
observa(media, J, Evento, J) :-
    J = jugador(Id, media, mente(K, _)),
    media_observar(Id, Evento, K).
observa(dificil, J, _, J).

% Una de cada diez veces acusa; el resto, sugiere.
accion_al_azar(Accion) :-
    al_azar(sospechoso, S),
    al_azar(arma, A),
    al_azar(lugar, L),
    (   maybe(0.1)
    ->  Accion = acusar(S, A, L)
    ;   Accion = sugerir(S, A, L)
    ).

al_azar(Tipo, Carta) :-
    findall(C, carta(Tipo, C), Cartas),
    random_member(Carta, Cartas).

%   ---------------------------------------------------------------------
%   Los eventos
%
%   Público: lo ven todos los jugadores y va al historial de la partida.
%
%       sugerencia(Quien, [S, A, L], Respuestas)
%           Quien sugiere. Respuestas son, en orden de turno, los jugadores
%           a los que se preguntó: no_pudo(J) si no tenía ninguna de las
%           tres cartas, y si alguien refutó, la lista termina con refuto(J).
%           Si nadie pudo refutar, todas son no_pudo(J).
%
%       acusacion(Quien, [S, A, L], Resultado)
%           Quien acusa. Resultado es acierta o falla.
%
%   Privado: lo ve un solo jugador y NO va al historial.
%
%       carta_vista(Refutador, Carta)
%           La carta que enseñó el Refutador. La ve solo el que sugirió.

%!  evento_publico(+Evento) is semidet.

evento_publico(sugerencia(_, [_, _, _], _)).
evento_publico(acusacion(_, [_, _, _], Resultado)) :-
    (   Resultado == acierta -> true ; Resultado == falla ).

%!  evento_privado(+Evento) is semidet.

evento_privado(carta_vista(_, _)).

%!  observar_todos(+Evento, +Jugadores, -Jugadores1) is det.
%
%   Entrega un evento público a todos los jugadores.

observar_todos(Evento, Jugadores, Jugadores1) :-
    (   evento_publico(Evento)
    ->  true
    ;   domain_error(evento_publico, Evento)
    ),
    maplist(observar_evento(Evento), Jugadores, Jugadores1).

%!  observar_a(+Id, +Evento, +Jugadores, -Jugadores1) is det.
%
%   Entrega un evento privado solo al jugador Id.

observar_a(Id, Evento, Jugadores, Jugadores1) :-
    (   evento_privado(Evento)
    ->  true
    ;   domain_error(evento_privado, Evento)
    ),
    maplist(observar_si(Id, Evento), Jugadores, Jugadores1).

% Ojo: maplist con predicados auxiliares, no con lambdas, para que no se
% copien los conocimientos con sus restricciones.
observar_evento(Evento, Jugador, Jugador1) :-
    observar(Jugador, Evento, Jugador1).

observar_si(Id, Evento, Jugador, Jugador1) :-
    (   Jugador = jugador(Id, _, _)
    ->  observar(Jugador, Evento, Jugador1)
    ;   Jugador1 = Jugador
    ).
