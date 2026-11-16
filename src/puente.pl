/*  Sherlog: el puente entre una partida y la página web.

    El jugador web es como el humano de la consola, pero en vez de
    preguntar por la terminal hace dos cosas:

        - Cuando le toca decidir, deja el estado a la vista y ESPERA un
          mensaje en una cola. Las peticiones HTTP dejan ahí la jugada.
        - Con todo lo que ve, va actualizando una FOTO del estado que las
          peticiones leen sin molestar al hilo de la partida.

    Cada partida corre en su propio hilo, y la cola y la foto son lo único
    que comparte con el resto. Por la cola y en la foto solo viajan datos
    planos (listas, cadenas, números): las restricciones del conocimiento
    viven y se consultan DENTRO del hilo de la partida.

    El bucle de la partida y el protocolo de jugador no cambian.

        juego.pl <- deduccion.pl <- ia.pl <- puente.pl <- jugador.pl
*/

:- module(puente,
          [ registrar_partida/2,
            olvidar_partida/1,
            foto_actual/2,
            publicar/2,
            actualizar_libreta/2,
            poner_retardo/1,
            poner_ritmo/2,
            ritmo_de/2,
            web_preguntar_accion/6,
            web_preguntar_carta/5,
            web_observar/5,
            estados_de_la_libreta/2
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(random)).
:- use_module(juego, [carta/2]).
:- use_module(deduccion).
:- use_module(ia, [media_observar/3, media_accion/2]).

:- dynamic foto_/3, cola_/2, retardo_/1, ritmo_/2.

retardo_(0.0).

%!  poner_retardo(+Segundos) is det.
%
%   Pausa tras cada jugada de otro jugador, para que la página pueda
%   seguir lo que ocurre. Con 0 (por defecto) no hay pausa. Con el átomo
%   manual no pasa nada hasta que la persona pulsa "Siguiente".

poner_retardo(Segundos) :-
    retractall(retardo_(_)),
    assertz(retardo_(Segundos)).

%!  poner_ritmo(+Id, +Segundos) is det.
%!  ritmo_de(+Id, -Segundos) is det.
%
%   El ritmo de una partida: segundos de pausa tras cada jugada de otro
%   jugador, o manual (paso a paso: la partida espera a que la persona
%   pulse "Siguiente"). Es de cada partida y se puede cambiar mientras se
%   juega. Si la partida no tiene el suyo, vale el retardo general.

poner_ritmo(Id, Segundos) :-
    with_mutex(sherlog_puente,
               ( retractall(ritmo_(Id, _)),
                 assertz(ritmo_(Id, Segundos)) )).

ritmo_de(Id, Segundos) :-
    (   ritmo_(Id, S) -> Segundos = S ; retardo_(Segundos) ).

%   ---------------------------------------------------------------------
%   La foto y la cola de cada partida

%!  registrar_partida(+Id, +Cola) is det.
%
%   Id es el identificador de la partida y Cola la cola de mensajes por la
%   que el jugador web recibe las jugadas.

registrar_partida(Id, Cola) :-
    with_mutex(sherlog_puente,
               ( retractall(cola_(Id, _)),
                 assertz(cola_(Id, Cola)) )).

%!  olvidar_partida(+Id) is det.

olvidar_partida(Id) :-
    with_mutex(sherlog_puente,
               ( retractall(cola_(Id, _)),
                 retractall(ritmo_(Id, _)),
                 retractall(foto_(Id, _, _)) )).

%!  foto_actual(+Id, -Foto) is semidet.
%
%   Foto es un diccionario con el estado actual de la partida, con su
%   número de versión. Falla si la partida no ha publicado nada aún.

foto_actual(Id, Foto) :-
    with_mutex(sherlog_puente, foto_(Id, _, Foto)).

%!  publicar(+Id, +Cambios) is det.
%
%   Mezcla los Cambios (un diccionario) con la foto y sube la versión.

publicar(Id, Cambios) :-
    actualizar(Id, const_cambios(Cambios)).

const_cambios(Cambios, _, Cambios).

% Calcula los cambios a partir de la foto actual y los aplica, todo bajo el
% cerrojo: nadie ve una foto a medias, y si el cálculo falla la foto no se toca.
actualizar(Id, Calcular) :-
    with_mutex(sherlog_puente,
               (   (   foto_(Id, V0, F0)
                   ->  true
                   ;   cola_(Id, _)            % primera foto de una partida viva
                   ->  V0 = 0, F0 = _{id: Id}
                   ;   throw(partida_abandonada)   % la partida ya se borró
                   ),
                   call(Calcular, F0, Cambios),
                   V is V0 + 1,
                   put_dict(Cambios, F0, F1),
                   put_dict(version, F1, V, F2),
                   retractall(foto_(Id, _, _)),
                   assertz(foto_(Id, V, F2))
               )).

%   ---------------------------------------------------------------------
%   Esperar la jugada

% Espera un mensaje de la cola de la partida. Abandonar la corta.
esperar(Id, Mensaje) :-
    (   cola_(Id, Cola)
    ->  true
    ;   throw(partida_abandonada)
    ),
    thread_get_message(Cola, Mensaje0),
    (   Mensaje0 == abandonar
    ->  throw(partida_abandonada)
    ;   Mensaje = Mensaje0
    ).

%!  web_preguntar_accion(+Id, +Yo, +Asistente, +Modo, +Vista, -Accion) is det.
%
%   Le toca jugar al jugador web. Deja el estado a la vista, avisa de que
%   se espera una acción y espera un mensaje accion(Tipo, [S, A, L]).

web_preguntar_accion(Id, Yo, Asistente, espectador, Vista, Accion) :-
    !,
    % Modo demo: la IA media juega con este conocimiento y la libreta la muestra.
    Vista = vista(Mano, _, _),
    calcular_porcentajes(Id, Asistente),
    publicar(Id, _{turno: Yo, mano: Mano}),
    media_accion(Asistente, Accion),
    pausar_un_poco(Id).
web_preguntar_accion(Id, Yo, Asistente, jugar, Vista, Accion) :-
    Vista = vista(Mano, _, _),
    calcular_porcentajes(Id, Asistente),
    publicar(Id, _{estado: esperando, turno: Yo, mano: Mano,
                   pendiente: _{tipo: accion}}),
    espera_accion(Id, Accion),
    publicar(Id, _{estado: jugando, pendiente: null}).

espera_accion(Id, Accion) :-
    esperar(Id, Mensaje),
    (   Mensaje = accion(Tipo, [S, A, L]),
        memberchk(Tipo, [sugerir, acusar])
    ->  Accion =.. [Tipo, S, A, L]
    ;   espera_accion(Id, Accion)
    ).

%!  web_preguntar_carta(+Id, +Modo, +Sugerencia, +Candidatas, -Carta) is det.
%
%   Al jugador web le toca refutar. Si solo tiene una carta no hay nada
%   que elegir; si tiene varias, espera un mensaje carta(Carta).

web_preguntar_carta(_, _, _, [Unica], Unica) :- !.
web_preguntar_carta(_, espectador, _, Candidatas, Carta) :- !,
    random_member(Carta, Candidatas).
web_preguntar_carta(Id, jugar, sugerencia(Quien, Cartas), Candidatas, Carta) :-
    publicar(Id, _{estado: esperando,
                   pendiente: _{tipo: carta,
                                sugerencia: _{quien: Quien, cartas: Cartas},
                                candidatas: Candidatas}}),
    espera_carta(Id, Candidatas, Carta),
    publicar(Id, _{estado: jugando, pendiente: null}).

espera_carta(Id, Candidatas, Carta) :-
    esperar(Id, Mensaje),
    (   Mensaje = carta(Elegida),
        memberchk(Elegida, Candidatas)
    ->  Carta = Elegida
    ;   espera_carta(Id, Candidatas, Carta)
    ).

%   ---------------------------------------------------------------------
%   Lo que ve el jugador web

%!  web_observar(+Id, +Yo, +Asistente, +Modo, +Evento) is det.
%
%   El jugador web ve un Evento del protocolo: lo anota en el historial,
%   se lo cuenta a su asistente (si lo tiene) y hace una pausa si lo ha
%   hecho otro jugador.

web_observar(Id, Yo, Asistente, Modo, Evento) :-
    actualizar(Id, cambios_por_evento(Evento)),
    observar_con_asistente(Id, Yo, Asistente, Evento),
    pausa(Id, Yo, Modo, Evento).

cambios_por_evento(sugerencia(Quien, Cartas, Respuestas), F, Cambios) :-
    !,
    get_dict(historial, F, Historial),
    length(Historial, N0),
    N is N0 + 1,
    maplist(respuesta_json, Respuestas, Rs),
    Entrada = _{n: N, tipo: sugerencia, quien: Quien, cartas: Cartas,
                respuestas: Rs, carta_vista: null},
    append(Historial, [Entrada], Historial1),
    get_dict(jugadores, F, Jugadores),
    siguiente_turno(Jugadores, Quien, Turno),
    Cambios = _{historial: Historial1, turno: Turno}.
cambios_por_evento(acusacion(Quien, Cartas, Resultado), F, Cambios) :-
    !,
    get_dict(historial, F, Historial),
    length(Historial, N0),
    N is N0 + 1,
    Entrada = _{n: N, tipo: acusacion, quien: Quien, cartas: Cartas,
                resultado: Resultado},
    append(Historial, [Entrada], Historial1),
    get_dict(jugadores, F, Jugadores0),
    (   Resultado == falla
    ->  maplist(eliminar_si(Quien), Jugadores0, Jugadores),
        siguiente_turno(Jugadores, Quien, Turno),
        Cambios = _{historial: Historial1, jugadores: Jugadores, turno: Turno}
    ;   Cambios = _{historial: Historial1}
    ).
cambios_por_evento(carta_vista(Refutador, Carta), F, Cambios) :-
    !,
    get_dict(historial, F, Historial),
    append(Anteriores, [Ultima], Historial),
    put_dict(carta_vista, Ultima, _{jugador: Refutador, carta: Carta}, Ultima1),
    append(Anteriores, [Ultima1], Historial1),
    Cambios = _{historial: Historial1}.
cambios_por_evento(_, _, _{}).

respuesta_json(no_pudo(J), _{jugador: J, resultado: no_pudo}).
respuesta_json(refuto(J), _{jugador: J, resultado: refuto}).

eliminar_si(Id, Jugador, Jugador1) :-
    (   get_dict(id, Jugador, Id)
    ->  put_dict(eliminado, Jugador, true, Jugador1)
    ;   Jugador1 = Jugador
    ).

% El siguiente jugador en círculo que no esté eliminado.
siguiente_turno(Jugadores, Quien, Turno) :-
    length(Jugadores, N),
    findall(Id,
            ( between(1, N, Paso),
              Id is (Quien - 1 + Paso) mod N + 1 ),
            Orden),
    (   member(Turno, Orden),
        member(J, Jugadores),
        get_dict(id, J, Turno),
        get_dict(eliminado, J, false)
    ->  true
    ;   Turno = Quien
    ).

% La pausa de la IA en el modo demo (sin evento): solo con ritmo en segundos.
pausar_un_poco(Id) :-
    ritmo_de(Id, Ritmo),
    (   number(Ritmo), Ritmo > 0 -> sleep(Ritmo) ; true ).

%   Tras un evento que la persona tiene que ver: o se espera el tiempo del
%   ritmo, o (paso a paso) se espera a que pulse "Siguiente".
pausa(Id, Yo, Modo, Evento) :-
    ritmo_de(Id, Ritmo),
    (   Ritmo == manual
    ->  (   pausa_manual(Yo, Modo, Evento) -> esperar_siguiente(Id) ; true )
    ;   number(Ritmo), Ritmo > 0, pausa_de_otro(Yo, Evento)
    ->  sleep(Ritmo)
    ;   true
    ).

% Con el ritmo en segundos solo se espera tras lo que hacen los demás.
pausa_de_otro(Yo, Evento) :-
    arg(1, Evento, Quien),
    integer(Quien),
    Quien \== Yo,
    memberchk(Evento, [sugerencia(_, _, _), acusacion(_, _, _)]).

% Paso a paso, hay una ventana por cada cosa que ocurre:
%   - la sugerencia de otro;
%   - el resultado de la tuya: al enseñarte la carta, o si nadie pudo refutar;
%   - la acusación de otro.
pausa_manual(Yo, _, sugerencia(Quien, _, Respuestas)) :-
    (   Quien \== Yo -> true
    ;   \+ memberchk(refuto(_), Respuestas)
    ).
pausa_manual(_, _, carta_vista(_, _)).
pausa_manual(Yo, Modo, acusacion(Quien, _, _)) :-
    (   Quien \== Yo -> true ; Modo == espectador ).

% La foto avisa de que se espera "Siguiente"; n es la entrada del historial
% que hay que enseñar.
esperar_siguiente(Id) :-
    actualizar(Id, pendiente_siguiente),
    espera_siguiente(Id).

pendiente_siguiente(F, _{estado: esperando, pendiente: _{tipo: siguiente, n: N}}) :-
    get_dict(historial, F, Historial),
    length(Historial, N).

espera_siguiente(Id) :-
    esperar(Id, Mensaje),
    (   Mensaje == siguiente
    ->  true
    ;   espera_siguiente(Id)
    ).

%   ---------------------------------------------------------------------
%   La libreta asistida
%
%   El asistente es el conocimiento del jugador (el mismo motor que usa la
%   IA media), alimentado con los mismos eventos que ve. Sin asistente es
%   la palabra none.

observar_con_asistente(_, _, none, _) :- !.
observar_con_asistente(Id, Yo, K, Evento) :-
    media_observar(Yo, Evento, K),
    actualizar_libreta(Id, K).

calcular_porcentajes(_, none) :- !.
calcular_porcentajes(Id, K) :-
    (   catch(probabilidades(K, Probs), _, fail)
    ->  actualizar(Id, con_porcentajes(Probs))
    ;   true
    ).

con_porcentajes(Probs, F, _{libreta: Libreta}) :-
    get_dict(libreta, F, Libreta0),
    maplist(poner_porcentaje(Probs), Libreta0, Libreta).

poner_porcentaje(Probs, Entrada, Entrada1) :-
    get_dict(carta, Entrada, Carta),
    (   memberchk(Carta-Pct, Probs)
    ->  put_dict(probabilidad, Entrada, Pct, Entrada1)
    ;   Entrada1 = Entrada
    ).

%!  actualizar_libreta(+Id, +K) is det.
%
%   Pone en la foto el estado de cada carta según el conocimiento K. Se
%   conservan los porcentajes de antes, salvo en las cartas que ya están
%   decididas (0 % si descartadas, 100 % si en el sobre).

actualizar_libreta(Id, K) :-
    estados_de_la_libreta(K, Nuevos),
    actualizar(Id, mezclar_libreta(Nuevos)).

mezclar_libreta(Nuevos, F, _{libreta: Libreta}) :-
    (   get_dict(libreta, F, Antes), Antes \== null
    ->  true
    ;   Antes = []
    ),
    maplist(conservar_porcentaje(Antes), Nuevos, Libreta).

conservar_porcentaje(Antes, Nueva, Resultado) :-
    get_dict(carta, Nueva, Carta),
    get_dict(estado, Nueva, Estado),
    (   Estado == descartada
    ->  Pct = 0.0
    ;   Estado == sobre
    ->  Pct = 100.0
    ;   member(A, Antes), get_dict(carta, A, Carta),
        get_dict(probabilidad, A, Pct0), Pct0 \== null
    ->  Pct = Pct0
    ;   Pct = null
    ),
    put_dict(probabilidad, Nueva, Pct, Resultado).

%!  estados_de_la_libreta(+K, -Libreta) is det.
%
%   Una entrada por carta, en el orden del mazo: su tipo y su estado
%   (descartada, dudosa o sobre), sin porcentaje todavía.

estados_de_la_libreta(K, Libreta) :-
    deducir(K, Estados),
    findall(_{carta: C, tipo: T, estado: E, probabilidad: null},
            ( carta(T, C), memberchk(C-E, Estados) ),
            Libreta).
