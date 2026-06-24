# shellcheck shell=bash

git_fixture_config() {
  local dir="$1"

  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name Test
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config tag.gpgsign false
}

make_git_fixture() {
  local remote seed clone

  remote="$BATS_TEST_TMPDIR/remote.git"
  seed="$BATS_TEST_TMPDIR/seed"
  clone="$BATS_TEST_TMPDIR/clone"

  mkdir -p "$seed"
  cp -R "$REPO"/. "$seed"/
  rm -rf "$seed/.git"

  git init --bare "$remote" >/dev/null
  git -C "$remote" symbolic-ref HEAD refs/heads/master
  git init "$seed" >/dev/null
  git_fixture_config "$seed"
  printf 'seed-v1\n' > "$seed/tracked.txt"
  git -C "$seed" add tracked.txt
  git -C "$seed" add .
  git -C "$seed" commit -m "initial release" >/dev/null
  git -C "$seed" branch -M master
  git -C "$seed" remote add origin "$remote"
  git -C "$seed" push -u origin master >/dev/null
  git -C "$seed" -c tag.gpgsign=false tag v0.1.0

  printf 'seed-v2\n' > "$seed/tracked.txt"
  git -C "$seed" commit -am "second release" >/dev/null
  git -C "$seed" -c tag.gpgsign=false tag v0.2.0
  git -C "$seed" push origin master --tags >/dev/null

  printf 'post-release\n' >> "$seed/tracked.txt"
  git -C "$seed" commit -am "post release" >/dev/null
  git -C "$seed" push origin master >/dev/null

  git clone --no-hardlinks "$remote" "$clone" >/dev/null
  git_fixture_config "$clone"

  export FIXTURE_REMOTE="$remote"
  export FIXTURE_SEED="$seed"
  export FIXTURE_CLONE="$clone"
}

publish_tag() {
  local version="$1"

  printf '%s\n' "$version" >> "$FIXTURE_SEED/tracked.txt"
  git -C "$FIXTURE_SEED" commit -am "release $version" >/dev/null
  git -C "$FIXTURE_SEED" -c tag.gpgsign=false tag "$version"
  git -C "$FIXTURE_SEED" push origin master --tags >/dev/null
}
