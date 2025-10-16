*   Introduce `ActiveSupport::ReplicationCoordinator` to support application behavior across multiple availability zones.

    For applications that replicate the database across multiple availability zones, an abstract
    base class `ActiveSupport::ReplicationCoordinator::Base` is introduced to simplify how
    applications discover whether they are in the active zone, and react to changes like
    failovers. It manages a background thread to periodically poll and cache the active zone state,
    and invokes callbacks when there are active/passive state changes.

    By default, Rails applications will be configured to use
    `ActiveSupport::ReplicationCoordinator::SingleZone` which always indicates that the app is in an
    "active" zone.

    Applications can build a custom replication coordinator and configure their app to use it by
    setting `config.replication_coordinator`.

    A test helper class `ActiveSupport::Testing::ReplicationCoordinator` is also introduced to
    simplify testing application behavior during active/passive state changes.

Please check [8-1-stable](https://github.com/rails/rails/blob/8-1-stable/activesupport/CHANGELOG.md) for previous changes.
