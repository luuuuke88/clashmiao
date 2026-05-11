package com.clashmiao.clashmiao;

import com.clashmiao.clashmiao.IServiceCallback;

interface IService {
  int getStatus();
  void registerCallback(in IServiceCallback callback);
  oneway void unregisterCallback(in IServiceCallback callback);
}