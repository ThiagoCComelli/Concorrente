#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>

typedef struct numbersStruct{
    double* array_numbersA;
    double* array_numbersB;
    double result;
    int start;
    int end;
    
} numbersStruct;

void *somador(void *arg){
    numbersStruct *numbersArg;
    numbersArg = (numbersStruct *)arg;

    // printf("%p \n\n",numbersArg->adress);

    for (int i = numbersArg->start; i < numbersArg->end; i++)
    {
        numbersArg->result += (numbersArg->array_numbersA[i] * numbersArg->array_numbersB[i]);
    }
    

    pthread_exit(NULL);
}

// Lê o conteúdo do arquivo filename e retorna um vetor E o tamanho dele
// Se filename for da forma "gen:%d", gera um vetor aleatório com %d elementos
//
// +-------> retorno da função, ponteiro para vetor malloc()ado e preenchido
// | 
// |         tamanho do vetor (usado <-----+
// |         como 2o retorno)              |
// v                                       v
double* load_vector(const char* filename, int* out_size);


// Avalia se o prod_escalar é o produto escalar dos vetores a e b. Assume-se
// que ambos a e b sejam vetores de tamanho size.
void avaliar(double* a, double* b, int size, double prod_escalar);

int main(int argc, char* argv[]) {
    srand(time(NULL));

    //Temos argumentos suficientes?
    if(argc < 4) {
        printf("Uso: %s n_threads a_file b_file\n"
               "    n_threads    número de threads a serem usadas na computação\n"
               "    *_file       caminho de arquivo ou uma expressão com a forma gen:N,\n"
               "                 representando um vetor aleatório de tamanho N\n", 
               argv[0]);
        return 1;
    }
  
    //Quantas threads?
    int n_threads = atoi(argv[1]);
    if (!n_threads) {
        printf("Número de threads deve ser > 0\n");
        return 1;
    }
    //Lê números de arquivos para vetores alocados com malloc
    int a_size = 0, b_size = 0;
    double* a = load_vector(argv[2], &a_size);
    if (!a) {
        //load_vector não conseguiu abrir o arquivo
        printf("Erro ao ler arquivo %s\n", argv[2]);
        return 1;
    }
    double* b = load_vector(argv[3], &b_size);
    if (!b) {
        printf("Erro ao ler arquivo %s\n", argv[3]);
        return 1;
    }
    
    //Garante que entradas são compatíveis
    if (a_size != b_size) {
        printf("Vetores a e b tem tamanhos diferentes! (%d != %d)\n", a_size, b_size);
        return 1;
    }

    //Calcula produto escalar. Paralelize essa parte
    double result = 0;

    // Calcula com uma thread só. Programador original só deixou a leitura 
    // do argumento e fugiu pro caribe. É essa computação que você precisa 
    // paralelizar

    if(n_threads > a_size){
        n_threads = a_size;
    }

    numbersStruct *numbers[n_threads];
    pthread_t t[n_threads];

    for(int i = 0; i < n_threads; i++){
        numbers[i] = malloc(sizeof(numbersStruct));
        numbers[i]->array_numbersA = a;
        numbers[i]->array_numbersB = b;
        numbers[i]->result = 0;
        numbers[i]->start = i*(int)(a_size/n_threads);


        if (i == (n_threads - 1)){
            numbers[i]->end = a_size;
        } else {
            numbers[i]->end = numbers[i]->start + (int)(a_size/n_threads);
        }
    }

    for (int i = 0; i < n_threads; i++)
    {
        pthread_create(&t[i],NULL,somador,(void *) numbers[i]);
    }

    for (int i = 0; i < n_threads; i++)
    {
        pthread_join(t[i],NULL);
    }

    for (int i = 0; i < n_threads; ++i){
        result += numbers[i]->result;
        free(numbers[i]);
    }
        
    
    //    +---------------------------------+
    // ** | IMPORTANTE: avalia o resultado! | **
    //    +---------------------------------+
    avaliar(a, b, a_size, result);

    //Libera memória
    free(a);
    free(b);

    return 0;
}
