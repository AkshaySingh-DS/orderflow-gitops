# Phase 6 boundary

Application CI remains responsible for producing and publishing a verified image. The GitOps repository remains responsible for deployment desired state. Argo CD is the only component introduced in this phase that reconciles Git state into the K3s cluster.

The application pipeline does not call `kubectl`, and Argo CD does not build application images.
