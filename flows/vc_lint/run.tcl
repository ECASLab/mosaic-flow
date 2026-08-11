# VC Lint command names can vary by installed release. This file is the only
# version-specific adapter. It must read $env(RTL_FILELIST), select
# $env(DESIGN_TOP), run the approved lint goal and return an error when unresolved
# violations exceed the repository policy.
error "VC Lint adapter is not configured for the installed release"
