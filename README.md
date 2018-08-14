# jrun

An easy way to run Java classes from the command line.

The idea came from this neat
[Cloudflare blog post](https://blog.cloudflare.com/using-go-as-a-scripting-language-in-linux/)
about `binfmt_misc` for Go-lang. After seeing that Kotlin is
[also ready for scripting](https://github.com/holgerbrandl/kscript),
I wanted to run my Kotlin scripts like `./hello.kt` without having to 
compile them first to include all their dependencies in a single
binary. So I wrote [krun](https://github.com/jbuhacoff/kotlin-krun).
Then I thought... why not Java classes also?

Let's say you have a Java class `hello.java`:

    public class Main {

        public static void main(String[] args) {
            System.out.println("Hello World!");
        }

    }

Notice the class name inside the file is `Main`. This constraint makes it easier
to generate the executable `.jar` file, where your class will end up as a `Main.class`
file in the root package.

After installing `jrun` in your `PATH`, you can do this:

    jrun hello.java

If you register `jrun` with `binfmt_misc` then you can also do this:

    ./hello.java

The first time `jrun` encounters a script, it compiles it with `javac`.
Each subsequent time `jrun` encounters the same script, it skips compiling
it and runs the `.jar` file that was compiled the first time. The "same"
script is defined by the SHA-256 digest of the script file, so the time stamp,
filename, and path are irrelevant.

## Configuration

### Cache location

The compiled `.jar` files are stored in a `~/.jrun` directory. You can change
this by exporting the variable `JRUN_CACHE` with the path to a different location
that is writable. 

To avoid repetition you can create a file `~/.jrunrc` with the variable like this:

    JRUN_CACHE=/var/lib/jrun

### Class path

If the Java class imports classes that are not part of the JRE, you'll need
to set the class path for compiling and running the class. 

You can set the class path by creating an Ivy module file. Continuing the
`hello.java` example, let's say you have another file `hello.ivy.xml`:

    <?xml version="1.0"?>
    <ivy-module version="2.0">
      <info org="jrun" module="hello"/>
      <dependencies>
        <dependency org="org.slf4j" name="slf4j-api" rev="1.7.25" />
        <dependency org="ch.qos.logback" name="logback-classic" rev="1.2.3" />
      </dependencies>
    </ivy-module>

Java classes typically depend on other classes. A specially-formatted comment
in the `.java` file helps `jrun` set the class path in the manifest of the
compiled `.jar` file. Here is `hello.java` again with dependencies declared
in `hello.ivy.xml`:

    // @ivy hello.ivy.xml
    import org.slf4j.Logger;
    import org.slf4j.LoggerFactory;

    public class Main {
        final private static Logger LOG = LoggerFactory.getLogger(Main.class);

        public static void main(String[] args) {
            LOG.info("Hello World!");
        }

    }

Ivy downloads artifacts into `~/.ivy2/cache/` or whatever location you configure
in the XML file. 

### Proxy

To automatically download dependencies that are not already in the cache,
Ivy will connect to remote repositories. If you have an HTTP or HTTPS proxy
you can configure it in `~/.jrunrc` like this:

    HTTP_PROXY_HOST=http-proxy.example.com
    HTTP_PROXY_PORT=8080
    HTTPS_PROXY_HOST=https-proxy.example.com
    HTTPS_PROXY_PORT=8443

If these variables are defined and there is no ~/.m2/settings.xml file, the
`jrun` script will create it automatically with the values from these variables.

## Pre-requisites

The following programs need to be in the `PATH`:

* java
* javac
* jar
* ant
* mvn

And the following standard utilities also need to be in the `PATH`:

* mktemp
* sed
* echo
* mv
* rm
* mkdir
* head
* tail
* fold

## How to install

To register `jrun` with `binfmt_misc` in a Docker container,
you must create the container with the `--privileged` option.

### From GitHub

    git clone https://github.com/jbuhacoff/java-jrun.git
    ( cd java-jrun && make install )

### From source .tgz

    tar xzf jrun-0.1.tar.gz
    ( cd jrun-0.1 && make install )

## Maintenance

There's one test script that demonstrates `jrun` with the cache:

    make test

This command will create the `.tar.gz` for distribution:

    make package

## Performance

Using `jrun` adds very little overhead compared to using `java -jar ...` directly for a
pre-compiled `.jar` file.  When a new or edited `.java` file is compiled, if new
dependencies are declared they will be downloaded automatically. That delay may be 
significant but it's essentially the same time you would have waited for that to
happen while building a `.jar` the first time.

Here are some samples from my laptop, informally:

`hello.java` first time:

    time jrun hello.java

    Hello World!

    real    0m0.858s
    user    0m1.144s
    sys     0m0.076s

`hello.java` second time:

    time jrun hello.java

    Hello World!

    real    0m0.106s
    user    0m0.092s
    sys     0m0.008s

`hello-ivy-convention.java` first time:

    time jrun hello-ivy-convention.java

    11:50:50.757 [main] INFO Main - Hello World!

    real    0m2.232s
    user    0m3.508s
    sys     0m0.116s
    
`hello-ivy-convention.java` second time:

    time jrun hello-ivy-convention.java

    11:50:51.010 [main] INFO Main - Hello World!

    real    0m0.241s
    user    0m0.268s
    sys     0m0.024s

`hello-ivy-comment.java` first time:

    time jrun hello-ivy-comment.java

    11:50:53.214 [main] INFO Main - Hello World!

    real    0m2.215s
    user    0m3.340s
    sys     0m0.172s

`hello-ivy-comment.java` second time:

    time jrun hello-ivy-comment.java

    11:50:53.418 [main] INFO Main - Hello World!

    real    0m0.193s
    user    0m0.232s
    sys     0m0.016s

The times vary, on my system the "real" time is sometimes +/- 0.010s from this
typical measurement.

