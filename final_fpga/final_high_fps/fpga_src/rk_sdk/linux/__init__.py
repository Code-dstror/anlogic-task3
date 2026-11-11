from pkgutil import extend_path

# Use the installed receiver and RK shell with this image's private SDK.
__path__ = extend_path(__path__, __name__)
