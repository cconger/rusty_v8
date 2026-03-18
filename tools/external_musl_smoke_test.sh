#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: external_musl_smoke_test.sh [--run] [--keep-temp]

Creates a temporary external Cargo project that depends on the local rusty_v8
checkout by path and builds it for x86_64-unknown-linux-musl.

Environment overrides:
  CARGO               Cargo binary to use (default: cargo)
  CARGO_TARGET_DIR    Cargo target dir to use
  MUSL_TARGET         Rust target triple (default: x86_64-unknown-linux-musl)
  PYTHONSAFEPATH      Passed through to the dependency build (default: 1)
  V8_FROM_SOURCE      Passed through to the dependency build (default: 1)
EOF
}

run_binary=0
keep_temp=0

while (($#)); do
  case "$1" in
    --run)
      run_binary=1
      ;;
    --keep-temp)
      keep_temp=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/rusty_v8-external-musl.XXXXXX")"
if [[ "${keep_temp}" -eq 0 ]]; then
  trap 'rm -rf "${tmpdir}"' EXIT
fi

mkdir -p "${tmpdir}/src"

cat > "${tmpdir}/Cargo.toml" <<EOF
[package]
name = "rusty_v8_external_musl_smoke"
version = "0.1.0"
edition = "2024"

[dependencies]
v8 = { path = "${repo_root}" }
EOF

cat > "${tmpdir}/src/main.rs" <<'EOF'
fn main() {
  let platform = v8::new_default_platform(0, false).make_shared();
  v8::V8::initialize_platform(platform);
  v8::V8::initialize();

  {
    let isolate = &mut v8::Isolate::new(v8::CreateParams::default());
    v8::scope!(let handle_scope, isolate);
    let context = v8::Context::new(handle_scope, Default::default());
    let scope = &mut v8::ContextScope::new(handle_scope, context);

    let source = v8::String::new(scope, "'musl' + ' smoke test'").unwrap();
    let script = v8::Script::compile(scope, source, None).unwrap();
    let result = script.run(scope).unwrap();
    let result = result.to_string(scope).unwrap();
    println!("{}", result.to_rust_string_lossy(scope));
  }

  unsafe {
    v8::V8::dispose();
  }
  v8::V8::dispose_platform();
}
EOF

cargo_bin="${CARGO:-cargo}"
target="${MUSL_TARGET:-x86_64-unknown-linux-musl}"
target_dir="${CARGO_TARGET_DIR:-/tmp/rusty_v8-external-musl-target}"
python_safepath="${PYTHONSAFEPATH:-1}"
v8_from_source="${V8_FROM_SOURCE:-1}"

echo "external project: ${tmpdir}"
echo "cargo target dir: ${target_dir}"

env \
  PYTHONSAFEPATH="${python_safepath}" \
  V8_FROM_SOURCE="${v8_from_source}" \
  CARGO_TARGET_DIR="${target_dir}" \
  "${cargo_bin}" build \
  --manifest-path "${tmpdir}/Cargo.toml" \
  --target "${target}"

if [[ "${run_binary}" -eq 1 ]]; then
  binary_path="${target_dir}/${target}/debug/rusty_v8_external_musl_smoke"
  "${binary_path}"
fi
