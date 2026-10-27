<script lang="ts">
  import { notify } from "../store/stores";
  import { fly } from 'svelte/transition';
  import { onMount } from 'svelte';

  const NOTIFICATION_DURATION = 3000; // 3 seconds
  let progress = 100;
  let progressInterval: NodeJS.Timer;

  $: notificationData = typeof $notify === 'object'
    ? $notify
    : { message: $notify, type: 'info' };

  $: notificationType = notificationData.type || 'info';
  $: notificationIcon = notificationType === 'error'
    ? 'fa-circle-exclamation'
    : notificationType === 'success'
      ? 'fa-circle-check'
      : 'fa-circle-info';

  $: notificationColor = notificationType === 'error'
    ? 'text-bank-red'
    : notificationType === 'success'
      ? 'text-bank-green'
      : 'text-bank-green';

  $: if ($notify) {
    startTimer();
  } else {
    clearInterval(progressInterval);
    progress = 100;
  }

  function startTimer() {
    clearInterval(progressInterval);
    progress = 100;
    
    const startTime = Date.now();
    progressInterval = setInterval(() => {
      const elapsed = Date.now() - startTime;
      progress = Math.max(0, 100 - (elapsed / NOTIFICATION_DURATION) * 100);
      
      if (progress <= 0) {
        notify.set(null);
        clearInterval(progressInterval);
      }
    }, 10);
  }

  onMount(() => {
    return () => clearInterval(progressInterval);
  });
</script>

{#if $notify}
  <div 
    class="fixed right-[5%] top-[5%] z-50 max-w-md animate-fadeIn"
    transition:fly={{ x: 20, duration: 300 }}
  >
    <div class="bg-fleeca-card rounded-lg shadow-lg overflow-hidden border border-fleeca-border">
      <div class="relative h-1 bg-fleeca-bg">
        <div
          class="absolute left-0 top-0 h-full transition-all duration-100 ease-linear"
          class:bg-bank-red={notificationType === 'error'}
          class:bg-bank-green={notificationType === 'success' || notificationType === 'info'}
          style="width: {progress}%"
        ></div>
      </div>
      
      <div class="p-4 flex items-start gap-3">
        <div class="w-10 h-10 rounded-full bg-fleeca-bg flex items-center justify-center flex-shrink-0">
          <i class={`fa-solid ${notificationIcon} ${notificationColor} text-lg`}></i>
        </div>
        
        <div class="flex-1 min-w-0">
          {#if notificationData.title}
            <h3 class="text-fleeca-text font-semibold text-sm mb-1 truncate">
              {notificationData.title}
            </h3>
          {/if}
          <p class="text-fleeca-text-secondary text-sm break-words">
            {notificationData.message || notificationData}
          </p>
        </div>

        <button
          aria-label="Close"
          class="text-fleeca-text-secondary hover:text-fleeca-text transition-colors p-1"
          on:click={() => notify.set(null)}
        >
          <i class="fa-solid fa-xmark"></i>
        </button>
      </div>
    </div>
  </div>
{/if}
