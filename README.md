Thermostat OpenShift
=============================

This repository contains a OpenShift templates and scripts for building and deploying Thermostat
components to an OpenShift instance. This deployment is currently intended for use with OpenShift Online 3
Starter. As such, resource limits are imposed on various components to fit within the quotas included with
the Starter tier.

Usage
---------------------------------
To build and deploy all Thermostat components monitoring a Wildfly test application:

    $ bash deploy-thermostat.sh

This deploys a MongoDB image used for ephemeral storage, the Thermostat Web Gateway that also serves
the Web Client, and the Thermostat Agent running alongside the Wildfly test application.
