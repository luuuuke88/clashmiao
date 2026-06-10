#!/bin/sh
set -eu

case "${CONFIGURATION:-}" in
  Debug) exit 0 ;;
esac

registrant="${PROJECT_DIR}/Runner/GeneratedPluginRegistrant.m"
[ -f "$registrant" ] || exit 0

/usr/bin/perl -0pi -e 's/#if __has_include\(<integration_test\/IntegrationTestPlugin\.h>\).*?#endif\n\n//s; s/\n\s*\[IntegrationTestPlugin registerWithRegistrar:\[registry registrarForPlugin:@"IntegrationTestPlugin"\]\];\n/\n/s;' "$registrant"
