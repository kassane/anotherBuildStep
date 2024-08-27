// Any copyright is dedicated to the Public Domain.
// https://creativecommons.org/publicdomain/zero/1.0/

@main
struct HelloWorld {
    static func main() {
        let message = "Hello, World!"
        message.withCString { cString in
            println(cString)
        }
    }
}
