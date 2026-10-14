import sys

# black magic
import tests  # noqa: F401
from tests.test_all import main

sys.exit(main())
