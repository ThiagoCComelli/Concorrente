#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <string.h>

//       (pai)      
//         |        
//    +----+----+
//    |         |   
// filho_1   filho_2


// ~~~ printfs  ~~~
// pai (ao criar filho): "Processo pai criou %d\n"
//    pai (ao terminar): "Processo pai finalizado!\n"
//  filhos (ao iniciar): "Processo filho %d criado\n"

// Obs:
// - pai deve esperar pelos filhos antes de terminar!


int main(int argc, char** argv) {

    // ....

    /*************************************************
     * Dicas:                                        *
     * 1. Leia as intruções antes do main().         *
     * 2. Faça os prints exatamente como solicitado. *
     * 3. Espere o término dos filhos                *
     *************************************************/
    int j;
    pid_t pid;
    pid = fork();

    if(pid < 0){
        return 1;
    } else if (pid == 0){
        printf("Processo filho %d criado\n", getpid()); 
        exit(0);
    } else {
        printf("Processo pai criou %d\n", pid);

        pid = fork();

        if(pid < 0){
            return 1;
        } else if (pid == 0){
            printf("Processo filho %d criado\n", getpid());
            exit(0);
        } else {
            printf("Processo pai criou %d\n", pid);

            while(wait(NULL) > 0){
            }

            printf("Processo pai finalizado!\n");
        }
    }

     

    return 0;
}
