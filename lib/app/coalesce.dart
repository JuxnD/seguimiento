/// Envuelve una tarea para que nunca corra dos veces a la vez **y** no se
/// pierda ningún pedido: si llega uno mientras corre, se repite al terminar
/// (una sola vez, por muchos que lleguen).
Future<void> Function() coalesce(Future<void> Function() task) {
  Future<void>? running;
  var again = false;
  Future<void> loop() async {
    try {
      do {
        again = false;
        await task();
      } while (again);
    } finally {
      // Si la tarea lanza, el siguiente pedido debe poder correr igual.
      running = null;
    }
  }

  return () {
    if (running != null) {
      again = true;
      return running!;
    }
    return running = loop();
  };
}
