import time

class Tasks():
    def __init__(self,proccessId,matrixIdx):
        self.tasksRows = {'0':None,'1':None,'2':None,'3':None,'4':None,'5':None,'6':None,'7':None,'8':None}
        self.tasksCol = {'0':None,'1':None,'2':None,'3':None,'4':None,'5':None,'6':None,'7':None,'8':None}
        self.tasksArea = {'0':None,'1':None,'2':None,'3':None,'4':None,'5':None,'6':None,'7':None,'8':None}
             
        self.__areas = {1:[0,0],2:[0,3],3:[0,6],
                        4:[3,0],5:[3,3],6:[3,6],
                        7:[6,0],8:[6,3],9:[6,6]}
        self.__completed = 0
        self.__error = 0
        self.__log = f'\nProcesso {proccessId} resolve quebra-cabeças {matrixIdx}:\n'
        self.__proccessId = proccessId
        self.__matrixIdx = matrixIdx
        self.__threadsIds = []
    
    def getThreadsIds(self):
        return self.__threadsIds
    
    def setThreadsIds(self,threadId):
        # time.sleep(0.000000000000001)
        if threadId not in self.__threadsIds:
            self.__threadsIds.append(threadId)

    def getTasks(self):
        return self.__tasks
    
    def getCompleted(self):
        return self.__completed
    
    def setCompleted(self):
        self.__completed += 1

    def getError(self):
        return self.__error
    
    def setError(self):
        self.__error += 1
    
    def getAreas(self):
        return self.__areas
    
    def setErrorLogs(self,threadId,coord):
        self.__log += f'Thread {self.__threadsIds.index(threadId)}: erro na {coord}.\n'
    
    def setFinalLog(self):
        self.__log += f'Erros encontrados: {self.__error}.'
        print(self.__log)
    
    def getLogs(self):
        return self.__log
    
    def changeStateTask(self,nameTask,state):
        self.__tasks[nameTask] = state