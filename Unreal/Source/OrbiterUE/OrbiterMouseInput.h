#pragma once
#include "CoreMinimal.h"
struct FOrbiterMouseState;
// Local events from this game's window only; no global mouse monitoring.
class FOrbiterMouseInput {
public:
    FOrbiterMouseInput();
    ~FOrbiterMouseInput();
    void SetWindow(void *NativeWindow);
    void Consume(double &Horizontal,double &Vertical,double &Scroll);
private:
    TSharedPtr<FOrbiterMouseState,ESPMode::ThreadSafe> State;
    void *Monitor=nullptr;
};
