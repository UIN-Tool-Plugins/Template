/*
 * sysinfo_server.c - 系统信息 HTTP 后端
 *
 * 提供以下接口：
 *   GET /health  - 健康检查
 *   GET /info    - 系统信息（JSON）
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/utsname.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>

#define BUFFER_SIZE 4096

static int get_port() {
    char *port_str = getenv("PORT");
    return port_str ? atoi(port_str) : 8000;
}

static void handle_health(int client_fd) {
    const char *response =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: application/json\r\n"
        "Connection: close\r\n"
        "\r\n"
        "{\"status\":\"ok\"}";
    write(client_fd, response, strlen(response));
}

static void handle_info(int client_fd) {
    struct utsname uts;
    uname(&uts);

    char response[BUFFER_SIZE];
    snprintf(response, sizeof(response),
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: application/json\r\n"
        "Connection: close\r\n"
        "\r\n"
        "{"
        "\"system\":\"%s\","
        "\"release\":\"%s\","
        "\"machine\":\"%s\","
        "\"node\":\"%s\","
        "\"time\":\"%ld\""
        "}",
        uts.sysname,
        uts.release,
        uts.machine,
        uts.nodename,
        time(NULL)
    );
    write(client_fd, response, strlen(response));
}

static void handle_request(int client_fd) {
    char buffer[BUFFER_SIZE];
    int bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
    if (bytes_read <= 0) return;
    buffer[bytes_read] = '\0';

    if (strncmp(buffer, "GET /health", 11) == 0) {
        handle_health(client_fd);
    } else if (strncmp(buffer, "GET /info", 9) == 0) {
        handle_info(client_fd);
    } else {
        const char *response =
            "HTTP/1.1 404 Not Found\r\n"
            "Connection: close\r\n"
            "\r\n";
        write(client_fd, response, strlen(response));
    }
}

int main() {
    /* 客户端提前断开时不要被 SIGPIPE 杀掉 */
    signal(SIGPIPE, SIG_IGN);

    int port = get_port();
    int server_fd, client_fd;
    struct sockaddr_in addr;

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        return 1;
    }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(server_fd);
        return 1;
    }

    if (listen(server_fd, 5) < 0) {
        perror("listen");
        close(server_fd);
        return 1;
    }

    printf("SysInfo server running on port %d\n", port);
    fflush(stdout);

    while (1) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) continue;
        handle_request(client_fd);
        close(client_fd);
    }

    close(server_fd);
    return 0;
}
