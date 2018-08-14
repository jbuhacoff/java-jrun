#!/bin/sh

# if java is from sdkman, get the paths
if [ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
    source "$HOME/.sdkman/bin/sdkman-init.sh"
fi

prog=$PWD/src/main/script/jrun.sh

export JRUN_CACHE=$PWD/.test

mkdir -p $JRUN_CACHE
# clear the cached .jar files
rm -rf $HOME/.jrun

echo "testing: hello.java"
time $prog src/test/java/hello.java
time $prog src/test/java/hello.java

echo "testing: hello-ivy-convention.java"
time $prog src/test/java/hello-ivy-convention.java
time $prog src/test/java/hello-ivy-convention.java

echo "testing: hello-ivy-comment.java"
time $prog src/test/java/hello-ivy-comment.java
time $prog src/test/java/hello-ivy-comment.java
