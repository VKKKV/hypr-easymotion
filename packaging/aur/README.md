packaging/aur
=============

Two package bases:

    hypr-easymotion       tracks a release tag (source: #tag=v$pkgver)
    hypr-easymotion-git   tracks main           (source: #branch=main)

Install paths:

    /usr/bin/easymotion-render
    /usr/share/lua/5.5/easymotion/*.lua
    /usr/share/licenses/$pkgname/LICENSE
    /usr/share/doc/$pkgname/README.md

Steps to publish
----------------

1. Commit the tree, then tag the commit: git tag -a v0.1.0 -m v0.1.0
2. Push the tag to the origin that the PKGBUILD points at.
3. Regenerate metadata in each directory:

       makepkg --printsrcinfo > .SRCINFO

4. Copy PKGBUILD, the .install file and .SRCINFO into a clone of the AUR
   repository and push to its master branch:

       git clone ssh://aur@aur.archlinux.org/hypr-easymotion-git.git
       git add PKGBUILD hypr-easymotion-git.install .SRCINFO
       git commit -m "hypr-easymotion-git: initial import"
       git push

   The AUR rejects a push whose commit has no .SRCINFO, and only accepts the
   master branch.

Blockers before the first push
------------------------------

- The source URL must be anonymously cloneable. git.k174.dev currently asks
  for credentials over HTTPS, so AUR users cannot fetch the tarball.
- The pushed commit must build from a clean clone:

      git clone <url> /tmp/em && cd /tmp/em && zig build -Doptimize=ReleaseSafe

- A tag has to exist for the tag-based package; the -git package works
  without one.

Not covered here
----------------

- Zig versions drift. Arch ships the latest zig, and this project tracks it
  (0.17 today). When zig breaks the build, bump pkgrel after fixing upstream.
- namcap has not been run on the produced packages.
