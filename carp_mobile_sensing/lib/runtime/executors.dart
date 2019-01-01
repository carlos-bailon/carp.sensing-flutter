/*
 * Copyright 2018 Copenhagen Center for Health Technology (CACHET) at the
 * Technical University of Denmark (DTU).
 * Use of this source code is governed by a MIT-style license that can be
 * found in the LICENSE file.
 */

part of runtime;

abstract class Executor extends AbstractProbe {
  static final Device deviceInfo = new Device();
  StreamGroup<Datum> _group = StreamGroup<Datum>.broadcast();

  Study study;
  DataManager _dataManager;
  List<Probe> executors = new List<Probe>();

  Stream<Datum> get events => _group.stream;

  Executor(this.study) : assert(study != null, "Cannot initiate an Executor without a Study.") {
    this.name = study.name;
  }

  Future start() async {
    super.start();
    this._start();
  }

  Future _start();

  void pause() async {
    executors.forEach((executor) => executor.pause());
    super.pause();
  }

  void resume() async {
    executors.forEach((executor) => executor.resume());
    super.resume();
  }

  void stop() async {
    executors.forEach((executor) => executor.stop());
    super.stop();
  }
}

/// The [StudyExecutor] is responsible for executing the [Study].
/// For each task it starts a [TaskExecutor].
///
/// Note that the [StudyExecutor] in itself is a [Probe] and hence work as a 'super probe'.
///This - amongst other things - imply that you can listen to datum [events] from a study executor.
class StudyExecutor extends Executor {
  Study study;
  DataManager _dataManager;

  StudyExecutor(this.study) : super(study);

  void initialize() async {
    await Device.getDeviceInfo();
    print('Initializing Study Executor for study: ' + study.name);
    print(' platform     : ' + Device.platform.toString());
    print(' device ID    : ' + Device.deviceID.toString());
    print(' data manager : ' + dataManager.toString());

    await dataManager.initialize(study);
    events.listen(dataManager.onData, onError: dataManager.onError, onDone: dataManager.onDone);
  }

  DataManager get dataManager {
    if (_dataManager == null) {
      // if the data manager hasn't been set, then try to look it up in the [DataManagerRegistry].
      _dataManager = DataManagerRegistry.lookup(study.dataEndPoint.type);
    }
    return _dataManager;
  }

  Future _start() async {
    for (Task task in study.tasks) {
      TaskExecutor executor = new TaskExecutor(study, task);
      _group.add(executor.events);

      executors.add(executor);
      await executor.start();
    }
  }

  void stop() async {
    super.stop();
    if (dataManager != null) dataManager.close();
  }
}

/// The [TaskExecutor] is responsible for executing [Task]s in the [Study].
/// For each task it looks up appropriate [Probe]s to collect data.
///
///Note that the [TaskExecutor] in itself is a [Probe] and hence work as a 'super probe'.
///This - amongst other things - imply that you can listen to datum [events] from a task executor.
class TaskExecutor extends Executor {
  //List<Probe> _probes = new List<Probe>();
  Task task;

  TaskExecutor(Study study, this.task)
      : assert(task != null),
        super(study) {
    name = task.name;
  }

  Future initialize() async {
    print('Initializing Task Executor for task: $name ...');
  }

  Future _start() async {
    for (Measure measure in task.measures) {
      Probe probe = ProbeRegistry.create(measure);
      if ((probe != null) && (measure.enabled)) {
        executors.add(probe);
        _group.add(probe.events);
        await probe.initialize();

        // start the probe
        await probe.start();
      }
    }
  }

  Stream<Datum> get events => _group.stream;
}
