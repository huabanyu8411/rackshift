package io.rackshift.strategy.statemachine.handler;

import io.rackshift.strategy.statemachine.AbstractHandler;
import io.rackshift.strategy.statemachine.EventHandlerAnnotation;
import io.rackshift.strategy.statemachine.LifeEvent;
import io.rackshift.strategy.statemachine.LifeStatus;

@EventHandlerAnnotation(LifeEvent.POST_OS_WORKFLOW_START)
public class OsWorkflowStartHandler extends AbstractHandler {
    @Override
    public void handleMyself(LifeEvent event) {
        changeStatus(event, LifeStatus.deploying, true);
    }
}
