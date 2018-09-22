#!/bin/bash


get_ivy_jar_path() {
    local tmpdir=$(mktemp -d)
    (
        cd $tmpdir

        # if we need to download ivy.jar from internet and proxy settings are defined,
        # but there is no ~/.m2/settings.xml file then generate it with the proxy settings:
        if [ -n "$HTTP_PROXY_HOST" ] && [ -n "$HTTP_PROXY_PORT" ] && [ -n "$HTTPS_PROXY_HOST" ] && [ -n "$HTTPS_PROXY_PORT" ] && [ ! -f $HOME/.m2/settings.xml ]; then
            cat >$HOME/.m2/settings.xml <<EOF
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
                          https://maven.apache.org/xsd/settings-1.0.0.xsd">
    <proxies>
        <proxy>
            <id>http-proxy</id>
            <active>true</active>
            <protocol>http</protocol>
            <host>$HTTP_PROXY_HOST</host>
            <port>$HTTP_PROXY_PORT</port>
        </proxy>
        <proxy>
            <id>https-proxy</id>
            <active>true</active>
            <protocol>https</protocol>
            <host>$HTTPS_PROXY_HOST</host>
            <port>$HTTPS_PROXY_PORT</port>
        </proxy>
    </proxies>
</settings>
EOF
        fi

        cat >pom.xml <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>jrun</groupId>
    <artifactId>download-ivy</artifactId>
    <version>2.3.0</version>
    <packaging>pom</packaging>
    <dependencies>
        <dependency>
            <groupId>org.apache.ivy</groupId>
            <artifactId>ivy</artifactId>
            <version>2.3.0</version>
        </dependency>
    </dependencies>
    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-dependency-plugin</artifactId>
                <executions>
                    <execution>
                        <id>path-to-ivy-jar</id>
                        <phase>package</phase>
                        <goals>
                            <goal>build-classpath</goal>
                        </goals>
                        <configuration>
                            <includeTypes>jar</includeTypes>
                            <outputFile>ivy.classpath</outputFile>
                            <pathSeparator> </pathSeparator>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
EOF

        mvn package >&2
        if [ $? -ne 0 ] || [ ! -s ivy.classpath ]; then
            echo "cannot find ivy.jar" >&2
            return 1
        fi

        # if we're on cygwin we need the cygwin path:
        if which cygpath >/dev/null 2>/dev/null; then
            cygpath -m -f ivy.classpath
        else
            cat ivy.classpath
        fi
    )
    rm -rf $tmpdir
}

# find an existing ivy xml file for a specified java file
find_ivy_xml() {
    local jsfile_basename=${1:-$jsfile_basename}
    local jsfile=$jsfile_basename.java
    local jsfile_dirname=$(dirname $jsfile)
    local ivy_xml_file

    # 1. look for "// @ivy <path to ivy.xml>"  in the java file
    ivy_xml_file=$(cat $jsfile | grep -E '^\s*// @ivy ' | sed -e 's|^\s*// @ivy \s*||')
    if [ -n "$ivy_xml_file" ] && [ -f "$ivy_xml_file" ]; then
        echo "$ivy_xml_file"
        return 0
    fi

    # 1a. if ivyfile wasn't found exactly where specified, check again relative
    #     to jsfile in case the jsfile itself is not in current directory 
    #     (e.g.  jrun ./path/to/jsfile)
    if [ -n "$ivy_xml_file" ] && [ -f "$jsfile_dirname/$ivy_xml_file" ]; then
        echo "$jsfile_dirname/$ivy_xml_file"
        return 0
    fi

    # 2. assume basename + .ivy.xml extension and see if it exists
    ivy_xml_file="${jsfile_basename}.ivy.xml"
    if [ -n "$ivy_xml_file" ] && [ -f "$ivy_xml_file" ]; then
        echo "$ivy_xml_file"
        return 0
    fi

    return 1
}

# generate an ivy.xml file from comments in the java file like "// <ivy:dependency ... />"
generate_ivy_xml() {
    local jsfile_basename=${1:-$jsfile_basename}
    local jsfile=$jsfile_basename.java

    # TODO: ...
    return 1
}

# writes files `classpath` and `classpath.separator`
generate_classpath() {
    local jsfile_basename=${1:-$jsfile_basename}
    local jsfile=$jsfile_basename.java
    local ivyfile=${2:-$ivyfile}

    # if there is no external ivy file, check if we can generate one from comments
    # NOTE: this can be done after computing digest because comments are already part of the digest
    if [ -z "$ivyfile" ]; then
        ivyfile=$(generate_ivy_xml $jsfile_basename)
    fi

    # use ivy to generate the classpath
    if [ -n "$ivyfile" ]; then
        cat >ivysettings.xml <<'EOF'
<ivysettings>
    <settings defaultResolver="default"/>
    <property name="m2-pattern" value="${user.home}/.m2/repository/[organisation]/[module]/[revision]/[module]-[revision](-[classifier]).[ext]" override="false" />
    <resolvers>
        <chain name="default">
            <filesystem name="local-maven2" m2compatible="true" >
                <artifact pattern="${m2-pattern}"/>
                <ivy pattern="${m2-pattern}"/>
            </filesystem>
            <ibiblio name="central" m2compatible="true"/>
        </chain>
    </resolvers>
</ivysettings>
EOF

        # NOTE: we define antvar_* variables here so the literal strings (their values)
        # will be replaced into build.xml where ant will interpret them as variables;
        # if we just write values like `${ivy.classpath.text}` directly below the shell
        # would attempt to interpret them and give an error
        local antvar_ivy_classpath_text='${ivy.classpath.text}'
        local antvar_path_separator='${path.separator}'
        cat >build.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns:ivy="antlib:org.apache.ivy.ant" name="jrun" default="resolve">
    <target name="init">
        <path id="ivy.lib.path">
          <fileset file="$IVY_JAR"/>
        </path>
        <taskdef resource="org/apache/ivy/ant/antlib.xml" uri="antlib:org.apache.ivy.ant" classpathref="ivy.lib.path"/>
    </target>
    <target name="resolve" depends="init">
        <ivy:configure file="ivysettings.xml" />
        <ivy:resolve file="$ivyfile" />
        <ivy:cachepath pathid="ivy.classpath"/>
        <property name="ivy.classpath.text" refid="ivy.classpath"/>
        <echo file="classpath">$antvar_ivy_classpath_text</echo>
        <echo file="classpath.separator">${antvar_path_separator}</echo>
    </target>
</project>
EOF

        # references:
        # * https://docs.oracle.com/javase/7/docs/api/java/net/doc-files/net-properties.html
        # * https://ant.apache.org/manual/proxy.html
        ANT_OPTS=
        if [ -n "$HTTP_PROXY_HOST" ] && [ -n "$HTTP_PROXY_PORT" ]; then
            ANT_OPTS="$ANT_OPTS -Dhttp.proxyHost=$HTTP_PROXY_HOST -Dhttp.proxyPort=$HTTP_PROXY_PORT"
        fi
        if [ -n "$HTTPS_PROXY_HOST" ] && [ -n "$HTTPS_PROXY_PORT" ]; then
            ANT_OPTS="$ANT_OPTS -Dhttps.proxyHost=$HTTPS_PROXY_HOST -Dhttps.proxyPort=$HTTPS_PROXY_PORT"
        fi

        export ANT_OPTS
        ant >&2 || return 1
    fi
}

# writes file `MANIFEST.MF`
# preconditions: 
# * file classpath.separator exists and contains the value of java path.separator system property
# * variable CLASSPATH is defined and contains java class path with path.separator between entries
generate_manifest() {
    if [ -f classpath ]; then
        local path_separator=$(cat classpath.separator)
        local JRUN_CLASSPATH=$(tr $path_separator ' ' <<< $CLASSPATH)
        # max line length in MANIFEST.MF is 72 bytes
        # reference: https://docs.oracle.com/javase/1.5.0/docs/guide/jar/jar.html
        local classpath_line1=$(head --bytes=72 <<< "Class-Path: $JRUN_CLASSPATH")
        local classpath_rest=$(tail --bytes=+73 <<< "Class-Path: $JRUN_CLASSPATH" | fold -b71 | sed -e 's/^/ /')
    fi

    cat >MANIFEST.MF <<EOF
Manifest-Version: 1.0
Created-By: jrun
Main-Class: Main
$classpath_line1
$classpath_rest
EOF
}

compile_java_file() {
    local jsfile=${1:-$jsfile}
    local ivyfile=${2:-$ivyfile}
    tmpdir=$(mktemp -d)

    # copy files before entering tmp directory, in case paths are relative
    cp $jsfile $tmpdir/Main.java
    if [ -n "$ivyfile" ]; then
        cp $ivyfile $tmpdir/ivy.xml
        ivyfile=ivy.xml
    fi

    (
        cd $tmpdir
        # generate classpath with ivy
        generate_classpath Main $ivyfile || exit 1
        if [ -f classpath ]; then
            export CLASSPATH=$(cat classpath)
        fi
        # compile the class and write Main.class
        javac Main.java >&2 || exit 1
        # create jar with manifest
        generate_manifest || exit 1
        jar cvfm Main.jar MANIFEST.MF Main.class >&2 || exit 1
        # cache .jar file
        mv Main.jar $JRUN_CACHE/$jsfile_sha256.jar
    )
    local exitcode=$?
    rm -rf $tmpdir
    return $exitcode
}


if [ -f "$HOME/.jrunrc" ]; then
    source $HOME/.jrunrc
fi

JRUN_CACHE=${JRUN_CACHE:-$HOME/.jrun}

jsfile=$1
if [ ! -f $jsfile ]; then
    echo "file does not exist: $jsfile" >&2
    exit 1
fi
jsfile_dirname=$(dirname $jsfile)
jsfile_basename=$(basename $jsfile .java)

# if a separate ivyfile exists then we include it in the digest because if dependencies changed we need to recompile
ivyfile=$(find_ivy_xml $jsfile_dirname/$jsfile_basename)
jsfile_sha256=$(cat $jsfile $ivyfile | sha256sum | head -c 64)

if [ ! -f $JRUN_CACHE/$jsfile_sha256.jar ]; then
    # ensure we have a cache directory
    mkdir -p $JRUN_CACHE

    # ensure we have an ivy jar for ant
    if [ -z "$IVY_JAR" ] || [ ! -f "$IVY_JAR" ]; then
        IVY_JAR=$(get_ivy_jar_path)
        echo "IVY_JAR=$IVY_JAR" >> $HOME/.jrunrc
    fi

    compile_java_file $jsfile $ivyfile >&2 || exit 1
fi

# run the cached jar file
java -jar $JRUN_CACHE/$jsfile_sha256.jar
