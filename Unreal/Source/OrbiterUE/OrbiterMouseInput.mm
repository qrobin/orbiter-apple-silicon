#include "OrbiterMouseInput.h"
#include "Mac/CocoaThread.h"
#include "Misc/ScopeLock.h"
struct FOrbiterMouseState {
    FCriticalSection Mutex;
    void *Window=nullptr;
    double Horizontal=0,Vertical=0,Scroll=0;
    NSPoint LastPosition=NSZeroPoint;
    bool HavePosition=false;
};
FOrbiterMouseInput::FOrbiterMouseInput():State(MakeShared<FOrbiterMouseState,ESPMode::ThreadSafe>()){
    const auto Shared=State;
    MainThreadCall(^{
        id Token=[NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDragged|NSEventMaskMouseMoved|NSEventMaskLeftMouseDown|NSEventMaskLeftMouseUp|NSEventMaskScrollWheel)
            handler:^NSEvent *(NSEvent *Event){
                FScopeLock Lock(&Shared->Mutex);
                if(Shared->Window&&(void *)[Event window]==Shared->Window){
                    const NSEventType Type=[Event type];
                    if(Type==NSEventTypeScrollWheel)Shared->Scroll+=[Event scrollingDeltaY];
                    else {
                        const NSPoint Position=[Event locationInWindow];
                        const bool Dragging=Type==NSEventTypeLeftMouseDragged||
                            (Type==NSEventTypeMouseMoved&&([NSEvent pressedMouseButtons]&1));
                        if(Dragging){
                            double X=[Event deltaX],Y=[Event deltaY];
                            // Coalesced and accessibility-generated drags may have positions but zero deltas.
                            if(X==0&&Y==0&&Shared->HavePosition){
                                X=Position.x-Shared->LastPosition.x;Y=Shared->LastPosition.y-Position.y;
                            }
                            Shared->Horizontal+=X;Shared->Vertical+=Y;
                        }
                        Shared->LastPosition=Position;Shared->HavePosition=true;
                    }
                }
                return Event;
            }];
        Monitor=(void *)[Token retain];
    });
}
FOrbiterMouseInput::~FOrbiterMouseInput(){
    void *Saved=Monitor;
    if(Saved)MainThreadCall(^{id Token=(id)Saved;[NSEvent removeMonitor:Token];[Token release];});
}
void FOrbiterMouseInput::SetWindow(void *NativeWindow){
    FScopeLock Lock(&State->Mutex);
    if(State->Window!=NativeWindow){
        State->Window=NativeWindow;State->HavePosition=false;
        State->Horizontal=State->Vertical=State->Scroll=0;
    }
}
void FOrbiterMouseInput::Consume(double &Horizontal,double &Vertical,double &Scroll){
    FScopeLock Lock(&State->Mutex);
    Horizontal=State->Horizontal;Vertical=State->Vertical;Scroll=State->Scroll;
    State->Horizontal=State->Vertical=State->Scroll=0;
}
