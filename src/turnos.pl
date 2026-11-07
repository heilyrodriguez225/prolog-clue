/*  Sherlog: el bucle de la partida.

    El bucle lleva dos cosas de turno en turno:

        Partida     partida(Sobre, Manos, Turno, Eliminados, Historial)
                    lo que es verdad y lo que es público (PLAN.md §2)

        Jugadores   [jugador(Id, Tipo, Memoria), ...]
                    en orden de Id; cada uno con su memoria privada
                    (PLAN.md §3)

    El bucle habla con los jugadores solo mediante el protocolo de
    jugador.pl: nunca les pasa la partida, solo su vista.

    Al terminar, la partida devuelve

        fin(Ganador, Motivo, Partida, Jugadores)

    con Ganador el número del jugador que gana y Motivo igual a acierta
    (acusó bien) o ultimo (era el único que quedaba sin eliminar).
    Partida y Jugadores son el estado final, con el historial completo.

    Dependencias entre módulos (cada uno importa solo a los de su izquierda):

        juego.pl  <-  deduccion.pl  <-  jugador.pl  <-  turnos.pl
*/

:- module(turnos,
          [ iniciar_partida/3,
            jugador_con_id/3,
            reemplazar_jugador/3,
            accion_del_turno/4,
            accion_valida/1,
            orden_de_consulta/3,
            resolver_sugerencia/7,
            agregar_al_historial/3,
            jugar_sugerencia/6,
            eliminar_de_la_partida/3,
            jugar_acusacion/7,
            jugadores_en_juego/2,
            siguiente_turno/2,
            aplicar_accion/4,
            aplicar_accion/5,
            jugar/3,
            jugar/4
          ]).

:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(juego).
:- use_module(jugador).

%!  iniciar_partida(+Tipos, -Partida, -Jugadores) is det.
%
%   Crea una partida con un jugador por cada tipo de la lista, en orden:
%   iniciar_partida([humano, media, facil], P, Js) es una partida de 3
%   jugadores. Partida y Jugadores son el estado con el que empieza el
%   bucle. Se admiten de 3 a 5 jugadores.

iniciar_partida(Tipos, Partida, Jugadores) :-
    length(Tipos, N),
    nueva_partida(N, Partida),
    jugadores_iniciales(Partida, Tipos, Jugadores).

%!  jugador_con_id(+Id, +Jugadores, -Jugador) is det.
%
%   Jugador es el jugador número Id de la lista.

jugador_con_id(Id, Jugadores, Jugador) :-
    Jugador = jugador(Id, _, _),
    (   memberchk(Jugador, Jugadores)
    ->  true
    ;   existence_error(jugador, Id)
    ).

%!  reemplazar_jugador(+Jugadores, +Jugador1, -Jugadores1) is det.
%
%   Jugadores1 es la lista con Jugador1 en el lugar del jugador que tiene
%   su mismo Id. Es como se guarda la memoria nueva que devuelve cada
%   operación del protocolo.

reemplazar_jugador([], jugador(Id, _, _), _) :-
    existence_error(jugador, Id).
reemplazar_jugador([jugador(Id0, T0, M0)|Resto], Jugador1, Jugadores1) :-
    Jugador1 = jugador(Id, _, _),
    (   Id0 == Id
    ->  Jugadores1 = [Jugador1|Resto]
    ;   Jugadores1 = [jugador(Id0, T0, M0)|Resto1],
        reemplazar_jugador(Resto, Jugador1, Resto1)
    ).

%!  accion_del_turno(+Partida, +Jugadores, -Accion, -Jugadores1) is det.
%
%   Le pide su acción al jugador al que le toca (el de Turno en la
%   Partida). Accion es sugerir(S, A, L) o acusar(S, A, L). Jugadores1
%   guarda la memoria nueva de ese jugador.
%
%   El jugador solo recibe su vista (vista_de/3), nunca la Partida.
%   Si la acción no es válida es un error: una IA con un fallo no debe
%   poder corromper la partida.

accion_del_turno(Partida, Jugadores, Accion, Jugadores1) :-
    Partida = partida(_, _, Turno, Eliminados, _),
    (   memberchk(Turno, Eliminados)
    ->  domain_error(jugador_en_juego, Turno)
    ;   true
    ),
    jugador_con_id(Turno, Jugadores, Jugador),
    vista_de(Turno, Partida, Vista),
    elegir_accion(Jugador, Vista, Accion, Jugador1),
    (   accion_valida(Accion)
    ->  true
    ;   domain_error(accion_valida, Accion)
    ),
    reemplazar_jugador(Jugadores, Jugador1, Jugadores1).

%!  accion_valida(+Accion) is semidet.
%
%   Una acción es sugerir o acusar con un sospechoso, un arma y un lugar
%   que existen.

accion_valida(Accion) :-
    nonvar(Accion),
    Accion =.. [Que, S, A, L],
    memberchk(Que, [sugerir, acusar]),
    once(carta(sospechoso, S)),
    once(carta(arma, A)),
    once(carta(lugar, L)).

%!  orden_de_consulta(+Quien, +N, -Orden) is det.
%
%   Orden es la lista de jugadores a los que se pregunta cuando Quien
%   sugiere, en una partida de N jugadores: los siguientes en círculo,
%   hasta dar la vuelta, sin incluir a Quien.
%   Por ejemplo, orden_de_consulta(3, 4, O) da O = [4, 1, 2].

orden_de_consulta(Quien, N, Orden) :-
    N1 is N - 1,
    findall(Id,
            ( between(1, N1, Paso),
              Id is (Quien - 1 + Paso) mod N + 1 ),
            Orden).

%!  resolver_sugerencia(+Partida, +Jugadores, +Quien, +Cartas, -Respuestas, -Refutacion, -Jugadores1) is det.
%
%   Quien sugiere las Cartas = [S, A, L]. Se pregunta en orden a los
%   demás jugadores, también a los eliminados (siguen refutando). El
%   primero que tenga alguna de las tres cartas refuta y se deja de
%   preguntar.
%
%   Respuestas es la lista, en orden de consulta, de no_pudo(J) y, si
%   alguien refutó, termina con refuto(J). Es la misma lista del evento
%   público sugerencia/3.
%
%   Refutacion es mostrada(J, Carta), con la carta que J enseñó, o
%   ninguna si nadie pudo refutar.
%
%   A quien refuta se le pide la carta con elegir_carta_a_mostrar/5,
%   pasándole solo las Candidatas: las cartas de la sugerencia que tiene.

resolver_sugerencia(Partida, Jugadores, Quien, Cartas, Respuestas, Refutacion, Jugadores1) :-
    Partida = partida(_, Manos, _, _, _),
    length(Manos, N),
    orden_de_consulta(Quien, N, Orden),
    preguntar(Orden, Manos, Jugadores, Quien, Cartas, Respuestas, Refutacion, Jugadores1).

preguntar([], _, Jugadores, _, _, [], ninguna, Jugadores).
preguntar([Id|Ids], Manos, Jugadores, Quien, Cartas, Respuestas, Refutacion, Jugadores1) :-
    memberchk(Id-Mano, Manos),
    include(en_mano(Mano), Cartas, Candidatas),
    (   Candidatas == []
    ->  Respuestas = [no_pudo(Id)|Respuestas1],
        preguntar(Ids, Manos, Jugadores, Quien, Cartas, Respuestas1, Refutacion, Jugadores1)
    ;   jugador_con_id(Id, Jugadores, Jugador),
        elegir_carta_a_mostrar(Jugador, sugerencia(Quien, Cartas), Candidatas, Carta, Jugador1),
        (   memberchk(Carta, Candidatas)
        ->  true
        ;   domain_error(carta_de_las(Candidatas), Carta)
        ),
        Respuestas = [refuto(Id)],
        Refutacion = mostrada(Id, Carta),
        reemplazar_jugador(Jugadores, Jugador1, Jugadores1)
    ).

en_mano(Mano, Carta) :- memberchk(Carta, Mano).

%!  agregar_al_historial(+Partida, +Evento, -Partida1) is det.
%
%   Añade un evento público al final del historial (los más antiguos
%   primero). Un evento privado no puede entrar en el historial.

agregar_al_historial(partida(Sobre, Manos, Turno, Eliminados, Historial), Evento,
                     partida(Sobre, Manos, Turno, Eliminados, Historial1)) :-
    (   evento_publico(Evento)
    ->  true
    ;   domain_error(evento_publico, Evento)
    ),
    append(Historial, [Evento], Historial1).

%!  jugar_sugerencia(+Partida, +Jugadores, +Quien, +Cartas, -Partida1, -Jugadores1) is det.
%
%   Quien sugiere las Cartas. Se resuelve la sugerencia
%   (resolver_sugerencia/7) y se entera cada uno de lo que le toca:
%
%       - el evento público sugerencia/3 lo ven TODOS los jugadores y se
%         añade al historial de la partida;
%       - la carta que enseñaron, carta_vista/2, la ve SOLO quien sugirió
%         y no entra en el historial.

jugar_sugerencia(Partida, Jugadores, Quien, Cartas, Partida1, Jugadores1) :-
    resolver_sugerencia(Partida, Jugadores, Quien, Cartas, Respuestas, Refutacion, Jugadores0),
    Evento = sugerencia(Quien, Cartas, Respuestas),
    observar_todos(Evento, Jugadores0, Jugadores00),
    (   Refutacion = mostrada(Refutador, Carta)
    ->  observar_a(Quien, carta_vista(Refutador, Carta), Jugadores00, Jugadores1)
    ;   Jugadores1 = Jugadores00
    ),
    agregar_al_historial(Partida, Evento, Partida1).

%!  eliminar_de_la_partida(+Partida, +Quien, -Partida1) is det.
%
%   Quien queda eliminado: ya no juega turno, pero sigue refutando
%   (su mano y su lugar en la lista de jugadores no cambian). Los
%   eliminados se guardan en el orden en que van cayendo.

eliminar_de_la_partida(partida(Sobre, Manos, Turno, Eliminados, Historial), Quien,
                       partida(Sobre, Manos, Turno, Eliminados1, Historial)) :-
    append(Eliminados, [Quien], Eliminados1).

%!  jugar_acusacion(+Partida, +Jugadores, +Quien, +Cartas, -Resultado, -Partida1, -Jugadores1) is det.
%
%   Quien acusa a las Cartas = [S, A, L]. Resultado es acierta si son
%   exactamente las del sobre, y falla si no.
%
%   El evento público acusacion/3 lo ven todos y entra en el historial.
%   Si falla, Quien queda eliminado. El evento NO dice qué parte de la
%   acusación estaba mal: solo si acertó o no.

jugar_acusacion(Partida, Jugadores, Quien, Cartas, Resultado, Partida2, Jugadores1) :-
    Partida = partida(sobre(S, A, L), _, _, _, _),
    (   Cartas == [S, A, L]
    ->  Resultado = acierta
    ;   Resultado = falla
    ),
    Evento = acusacion(Quien, Cartas, Resultado),
    observar_todos(Evento, Jugadores, Jugadores1),
    agregar_al_historial(Partida, Evento, Partida1),
    (   Resultado == falla
    ->  eliminar_de_la_partida(Partida1, Quien, Partida2)
    ;   Partida2 = Partida1
    ).

%!  jugadores_en_juego(+Partida, -Ids) is det.
%
%   Ids son los jugadores que no están eliminados, en orden.

jugadores_en_juego(partida(_, Manos, _, Eliminados, _), Ids) :-
    findall(Id, ( member(Id-_, Manos), \+ memberchk(Id, Eliminados) ), Ids).

%!  siguiente_turno(+Partida, -Partida1) is det.
%
%   Pasa el turno al siguiente jugador en círculo que no esté eliminado.
%   Si todos los demás están eliminados, el turno se queda donde está.

siguiente_turno(partida(Sobre, Manos, Turno, Eliminados, Historial),
                partida(Sobre, Manos, Siguiente, Eliminados, Historial)) :-
    length(Manos, N),
    orden_de_consulta(Turno, N, Orden),
    (   member(Id, Orden),
        \+ memberchk(Id, Eliminados)
    ->  Siguiente = Id
    ;   Siguiente = Turno
    ).

%!  jugar(+Partida, +Jugadores, -Resultado) is det.
%
%   Juega la partida hasta que termina. Resultado es
%
%       fin(Ganador, Motivo, Partida, Jugadores)
%
%   donde Motivo es acierta (Ganador acusó bien) o ultimo (Ganador era el
%   único que quedaba sin eliminar). Partida y Jugadores son el estado
%   final, con el historial completo.
%
%   En cada turno: se le pide su acción al jugador al que le toca; si
%   sugiere, se resuelve la sugerencia y se pasa el turno; si acusa, se
%   resuelve la acusación y la partida termina si acierta.
%
%   Si pasan demasiados turnos sin terminar se lanza un error: es un
%   fallo de algún jugador (por ejemplo, que nunca acuse), no algo normal.

jugar(Partida, Jugadores, Resultado) :-
    jugar(Partida, Jugadores, [], Resultado).

%!  jugar(+Partida, +Jugadores, +Opciones, -Resultado) is det.
%
%   Como jugar/3, con Opciones:
%
%       termina_si_cae(Id)   si el jugador Id queda eliminado, la partida
%                            termina en ese momento, sin ganador:
%                            fin(ninguno, eliminado(Id), Partida, Jugadores)
%
%   Es lo que se usa con el jugador humano: cuando se equivoca no tiene
%   sentido que la partida siga solo entre IAs mientras él mira.
%   Sin opciones el bucle se comporta como siempre, y un eliminado sigue
%   refutando.

jugar(Partida, Jugadores, Opciones, Resultado) :-
    Partida = partida(_, _, _, Eliminados, _),
    jugadores_en_juego(Partida, Ids),
    (   member(termina_si_cae(Id), Opciones),
        memberchk(Id, Eliminados)
    ->  Resultado = fin(ninguno, eliminado(Id), Partida, Jugadores)
    ;   Ids = [Ganador]
    ->  Resultado = fin(Ganador, ultimo, Partida, Jugadores)
    ;   comprobar_que_no_se_eterniza(Partida),
        un_turno_completo(Partida, Jugadores, Opciones, Resultado)
    ).

un_turno_completo(Partida, Jugadores, Opciones, Resultado) :-
    accion_del_turno(Partida, Jugadores, Accion, Jugadores1),
    aplicar_accion(Accion, Partida, Jugadores1, Opciones, Resultado).

%!  aplicar_accion(+Accion, +Partida, +Jugadores, -Resultado) is det.
%!  aplicar_accion(+Accion, +Partida, +Jugadores, +Opciones, -Resultado) is det.
%
%   El jugador al que le toca hace la Accion elegida. Si sugiere, se
%   resuelve la sugerencia y el juego sigue con el siguiente turno. Si
%   acusa, se resuelve la acusación: si acierta la partida termina, y si
%   falla sigue con el siguiente turno (salvo que una de las Opciones
%   haga terminar la partida).
%   Resultado es el de jugar/4.

aplicar_accion(Accion, Partida, Jugadores, Resultado) :-
    aplicar_accion(Accion, Partida, Jugadores, [], Resultado).

aplicar_accion(Accion, Partida, Jugadores, Opciones, Resultado) :-
    Partida = partida(_, _, Turno, _, _),
    (   Accion = sugerir(S, A, L)
    ->  jugar_sugerencia(Partida, Jugadores, Turno, [S, A, L], Partida1, Jugadores1),
        pasar_al_siguiente(Partida1, Jugadores1, Opciones, Resultado)
    ;   Accion = acusar(S, A, L),
        jugar_acusacion(Partida, Jugadores, Turno, [S, A, L], Acierto, Partida1, Jugadores1),
        (   Acierto == acierta
        ->  Resultado = fin(Turno, acierta, Partida1, Jugadores1)
        ;   pasar_al_siguiente(Partida1, Jugadores1, Opciones, Resultado)
        )
    ).

pasar_al_siguiente(Partida, Jugadores, Opciones, Resultado) :-
    siguiente_turno(Partida, Partida1),
    jugar(Partida1, Jugadores, Opciones, Resultado).

% Cada sugerencia o acusación deja un evento en el historial.
limite_de_eventos(1000).

comprobar_que_no_se_eterniza(partida(_, _, _, _, Historial)) :-
    limite_de_eventos(Limite),
    length(Historial, N),
    (   N >= Limite
    ->  resource_error(limite_de_turnos(Limite))
    ;   true
    ).
